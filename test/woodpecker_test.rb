# frozen_string_literal: true

require_relative 'test_helper'

# rake woodpecker, run end to end in a scratch consumer repo. These pin the
# properties AGENTS.md lists under "Generated pipelines".
class WoodpeckerTest < Minitest::Test
  MATRIX = {
    'image_name' => 'test',
    'versions'   => { '17' => {}, '18' => {} },
    'variants'   => { '' => {}, 'pgvector' => {} }
  }.freeze

  PUBLISH = ['rake tag', 'rake push'].freeze

  def step(pipeline, name)
    pipeline['steps'].find { |s| s['name'] == name } || flunk("no step #{name}")
  end

  def names(pipeline, prefix = nil)
    all = pipeline['steps'].map { |s| s['name'] }
    prefix ? all.select { |n| n.start_with?("#{prefix}-") } : all
  end

  def dep_names(step)
    (step['depends_on'] || []).map { |d| d.is_a?(Hash) ? d['name'] : d }
  end

  def test_step_names_for_matrix
    pipeline, = generate_pipeline(MATRIX)
    assert_equal %w[build-17-base build-17-pgvector build-18-base build-18-pgvector], names(pipeline, 'build')
    assert_equal %w[rebuild-17-base rebuild-17-pgvector rebuild-18-base rebuild-18-pgvector], names(pipeline, 'rebuild')
    assert_equal %w[tag-17-base tag-17-pgvector tag-18-base tag-18-pgvector], names(pipeline, 'tag')
    assert_includes names(pipeline), 'check-tag'
  end

  def test_no_yaml_anchors
    _, raw = generate_pipeline(MATRIX)
    refute_match(/[&*]\d+\b/, raw)
  end

  def test_push_steps_never_publish
    pipeline, = generate_pipeline(MATRIX)
    names(pipeline, 'build').each do |name|
      s = step(pipeline, name)
      assert_empty s['commands'] & PUBLISH, name
      assert_equal [{ 'event' => %w[push manual], 'branch' => 'main' }], s['when']
    end
  end

  def test_rake_update_only_in_render_and_setup
    pipeline, = generate_pipeline(MATRIX)
    with_update = pipeline['steps'].select { |s| s['commands'].include?('rake update') }.map { |s| s['name'] }
    assert_equal %w[render setup], with_update
    names(pipeline, 'build').each { |n| assert_includes dep_names(step(pipeline, n)), 'render' }
    names(pipeline, 'tag').each { |n| assert_equal %w[setup check-tag], dep_names(step(pipeline, n)) }
  end

  def test_each_step_selects_exactly_one_image
    pipeline, = generate_pipeline(MATRIX)
    base = step(pipeline, 'build-17-base')
    assert_equal '17', base['environment']['VERSION']
    refute base['environment'].key?('VARIANT')
    assert_includes base['commands'], "export VARIANT=''"
    variant = step(pipeline, 'tag-18-pgvector')
    assert_equal %w[18 pgvector], variant['environment'].values_at('VERSION', 'VARIANT')
    refute_includes variant['commands'], "export VARIANT=''"
    pipeline['steps'].select { |s| s['environment']&.key?('VERSION') }.each do |s|
      assert_equal '1', s['environment']['KEEP_BUILD'], s['name']
    end
  end

  def test_no_variant_export_without_variants
    pipeline, = generate_pipeline('image_name' => 'test', 'versions' => { '1' => {} })
    refute_includes step(pipeline, 'build-1-base')['commands'], "export VARIANT=''"
  end

  def test_tag_steps_gated_by_own_version
    pipeline, = generate_pipeline(MATRIX)
    assert_equal [{ 'event' => 'tag', 'ref' => 'refs/tags/17' }, { 'event' => 'tag', 'ref' => 'refs/tags/v17' }],
                 step(pipeline, 'tag-17-pgvector')['when']
    assert_equal PUBLISH, step(pipeline, 'tag-17-pgvector')['commands'].last(2)
    refute step(pipeline, 'tag-17-base')['environment'].key?('CRUCIBLE_SKIP_UNCHANGED')
  end

  def test_rebuild_steps_publish_and_skip_unchanged
    pipeline, = generate_pipeline(MATRIX)
    names(pipeline, 'rebuild').each do |name|
      s = step(pipeline, name)
      assert_equal [{ 'event' => 'cron', 'cron' => 'rebuild' }], s['when']
      assert_equal PUBLISH, s['commands'].last(2)
      assert_equal '1', s['environment']['CRUCIBLE_SKIP_UNCHANGED']
    end
    pipeline['steps'].reject { |s| s['name'].start_with?('rebuild-') }.each do |s|
      refute s['environment']&.key?('CRUCIBLE_SKIP_UNCHANGED'), s['name']
    end
  end

  # The check-tag command must pass a tag naming a version and fail any other.
  def test_check_tag_command
    pipeline, = generate_pipeline(MATRIX.merge('versions' => { '1.2' => {}, '18' => {} }))
    command = step(pipeline, 'check-tag')['commands'].join("\n")
    { 'v1.2' => true, '1.2' => true, 'v18' => true, 'v1x2' => false, 'v17' => false, 'v18.1' => false }.each do |tag, ok|
      _out, status = Open3.capture2e({ 'CI_COMMIT_TAG' => tag }, 'sh', '-c', command)
      assert_equal ok, status.success?, "check-tag with #{tag}"
    end
  end

  # Unversioned repos publish on any tag and have no check-tag step.
  def test_unversioned_repo
    pipeline, = generate_pipeline('image_name' => 'test')
    assert_equal %w[render build-base rebuild-base setup tag-base], names(pipeline)
    assert_equal [{ 'event' => 'tag' }], step(pipeline, 'tag-base')['when']
    assert_equal %w[setup], dep_names(step(pipeline, 'tag-base'))
    refute step(pipeline, 'tag-base')['environment'].key?('VERSION')
  end

  def test_variant_depends_on
    pipeline, = generate_pipeline(MATRIX.merge('variants' => { '' => {}, 'pgvector' => { 'depends_on' => '' } }))
    assert_equal %w[render build-17-base], dep_names(step(pipeline, 'build-17-pgvector'))
    assert_equal %w[render rebuild-18-base], dep_names(step(pipeline, 'rebuild-18-pgvector'))
    assert_equal %w[render], dep_names(step(pipeline, 'build-17-base'))
  end

  # The pipeline covers the whole matrix whatever VERSION/VARIANT is set.
  def test_ignores_version_filter_in_environment
    ENV['VERSION'] = '17'
    pipeline, = generate_pipeline(MATRIX)
    assert_includes names(pipeline), 'build-18-base'
  end
end

class WoodpeckerExtraStepsTest < Minitest::Test
  BASE = WoodpeckerTest::MATRIX

  def with_steps(section)
    BASE.merge('woodpecker' => section)
  end

  def step(pipeline, name)
    pipeline['steps'].find { |s| s['name'] == name } || flunk("no step #{name}")
  end

  def optional(name)
    { 'name' => name, 'optional' => true }
  end

  def test_no_section_is_unchanged
    plain, = generate_pipeline(BASE)
    empty, = generate_pipeline(with_steps(nil))
    assert_equal plain, empty
  end

  def test_pre_step_default_wiring
    fetch = { 'name' => 'fetch', 'image' => 'alpine/git', 'environment' => { 'P' => { 'from_secret' => 's' } },
              'commands' => ['./fetch.sh'] }
    pipeline, raw = generate_pipeline(with_steps('pre_steps' => [fetch]))

    assert_equal 'fetch', pipeline['steps'].first['name']
    generated = step(pipeline, 'fetch')
    assert_equal fetch['environment'], generated['environment']
    assert_nil generated['depends_on']

    targets = pipeline['steps'].select { |s| s['name'] =~ /\A(build|rebuild|tag)-/ }
    assert_equal 12, targets.size
    targets.each { |s| assert_includes s['depends_on'], optional('fetch'), s['name'] }
    assert_equal targets.flat_map { |s| s['when'] }.uniq, generated['when']
    %w[render setup check-tag].each { |n| refute_includes step(pipeline, n)['depends_on'] || [], optional('fetch') }
    refute_match(/[&*]\d+\b/, raw)
  end

  def test_explicit_when_and_depends_on_are_kept
    narrow = [{ 'event' => 'push', 'branch' => 'main' }]
    pipeline, = generate_pipeline(with_steps(
      'pre_steps'  => [{ 'name' => 'only-push', 'image' => 'a', 'when' => narrow }],
      'post_steps' => [{ 'name' => 'notify', 'image' => 'a', 'depends_on' => ['tag-17-base'] }]
    ))
    assert_equal narrow, step(pipeline, 'only-push')['when']
    # Optional, because tag steps run on events where only-push is absent.
    assert_includes step(pipeline, 'tag-18-base')['depends_on'], optional('only-push')
    assert_equal ['tag-17-base'], step(pipeline, 'notify')['depends_on']
  end

  def test_post_step_default_wiring
    pipeline, = generate_pipeline(with_steps('post_steps' => [{ 'name' => 'bump', 'image' => 'a' }]))
    bump = pipeline['steps'].last
    assert_equal 'bump', bump['name']
    tags = pipeline['steps'].select { |s| s['name'].start_with?('tag-') }
    assert_equal tags.map { |s| optional(s['name']) }, bump['depends_on']
    assert_equal tags.flat_map { |s| s['when'] }.uniq, bump['when']
    refute(bump['when'].any? { |w| w['event'] == 'cron' })
  end

  def test_post_steps_on_rebuild
    pipeline, = generate_pipeline(with_steps('post_steps_on_rebuild' => true,
                                             'post_steps' => [{ 'name' => 'bump', 'image' => 'a' }]))
    bump = step(pipeline, 'bump')
    assert_includes bump['when'], { 'event' => 'cron', 'cron' => 'rebuild' }
    assert_includes bump['depends_on'], optional('rebuild-18-pgvector')
    assert_includes bump['depends_on'], optional('tag-18-pgvector')
  end

  def test_unversioned_post_step
    pipeline, = generate_pipeline('image_name' => 'test',
                                  'woodpecker' => { 'post_steps' => [{ 'name' => 'bump', 'image' => 'a' }] })
    assert_equal [{ 'event' => 'tag' }], step(pipeline, 'bump')['when']
    assert_equal [optional('tag-base')], step(pipeline, 'bump')['depends_on']
  end

  def test_validation_errors
    {
      { 'pre_steps' => [{ 'name' => 'build-x' }] }              => /'build-x' clashes with generated step names/,
      { 'post_steps' => [{ 'name' => 'tag-notify' }] }          => /'tag-notify' clashes/,
      { 'post_steps' => [{ 'name' => 'check-tag' }] }           => /'check-tag' clashes/,
      { 'pre_steps' => [{ 'name' => 'render' }] }               => /'render' clashes/,
      { 'pre_steps' => [{ 'name' => 'a' }], 'post_steps' => [{ 'name' => 'a' }] } => /'a' is used more than once/,
      { 'pre_steps' => [{ 'image' => 'a' }] }                   => /pre_steps\[0\] has no name/,
      { 'pre_steps' => [{ 'name' => '' }] }                     => /has no name/,
      { 'pre_steps' => [{ 'name' => 17 }] }                     => /name must be a string/,
      { 'pre_steps' => ['fetch'] }                              => /pre_steps\[0\] must be a mapping/,
      { 'pre_steps' => { 'name' => 'a' } }                      => /pre_steps must be a list/,
      { 'pre_step' => [] }                                      => /unknown woodpecker key\(s\): pre_step/,
      { 'post_steps_on_rebuild' => 'yes' }                      => /post_steps_on_rebuild must be true or false/
    }.each do |section, message|
      assert_match message, rake_woodpecker_error(with_steps(section)), section.inspect
    end
    assert_match(/woodpecker must be a mapping/, rake_woodpecker_error(with_steps('oops')))
  end

  def test_metadata_is_not_mutated
    metadata = { 'woodpecker' => { 'pre_steps' => [{ 'name' => 'a', 'image' => 'x' }] } }
    extra = woodpecker_extra_steps(metadata)
    wire_woodpecker_extra_steps([{ 'name' => 'build-1', 'when' => [{ 'event' => 'push' }] }], extra)
    assert_equal({ 'name' => 'a', 'image' => 'x' }, metadata['woodpecker']['pre_steps'].first)
  end
end
