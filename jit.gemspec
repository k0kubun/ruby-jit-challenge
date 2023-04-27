require_relative 'lib/jit/version'

Gem::Specification.new do |spec|
  spec.name = 'jit'
  spec.version = JIT::VERSION
  spec.authors = ['Takashi Kokubun']
  spec.email = ['takashikkbn@gmail.com']

  spec.summary = 'Ruby JIT Challenge'
  spec.description = 'Ruby JIT Challenge'
  spec.homepage = 'https://github.com/k0kubun/ruby-jit-challenge'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|circleci)|appveyor)})
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
end
