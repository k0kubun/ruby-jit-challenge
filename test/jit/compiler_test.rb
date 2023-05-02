require 'minitest/autorun'
require 'open3'

class JITCompilerTest < Minitest::Test
  REPO_ROOT = File.expand_path('../..', __dir__)

  def test_none
    assert_jit('test/none.rb', 'nil')
  end

  def test_plus
    assert_jit('test/plus.rb', '3')
  end

  def test_minus
    assert_jit('test/minus.rb', '2')
  end

  def test_local
    assert_jit('test/local.rb', '2')
  end

  def test_lt
    assert_jit('test/lt.rb', "true\nfalse")
  end

  def test_branch
    assert_jit('test/branch.rb', "1\n0")
  end

  def test_send
    assert_jit('test/send.rb', '2')
  end

  def test_fib
    assert_jit('test/fib.rb', '2178309')
  end

  private

  def assert_jit(path, expected)
    stdout, stderr, status = Bundler.with_unbundled_env do
      Open3.capture3(
        RbConfig.ruby, "-r#{REPO_ROOT}/lib/jit.rb", '--rjit=pause',
        '--rjit-call-threshold=3', File.expand_path(path, REPO_ROOT)
      )
    end
    assert_equal 0, status.exitstatus,
      "stdout:\n```\n#{stdout}```\n\nstderr:\n```\n#{stderr}```"
    assert_equal '', stderr
    assert_equal "#{expected}\n", stdout
  end
end
