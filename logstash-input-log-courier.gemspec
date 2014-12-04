Gem::Specification.new do |gem|
  gem.name              = 'logstash-input-log-courier'
  gem.version           = '1.2'
  gem.description       = 'Log Courier Input Logstash Plugin'
  gem.summary           = 'Receive events from Log Courier and Logstash using the Log Courier protocol'
  gem.homepage          = 'https://github.com/driskell/log-courier'
  gem.authors           = ['Jason Woods']
  gem.email             = ['devel@jasonwoods.me.uk']
  gem.licenses          = ['Apache']
  gem.rubyforge_project = 'nowarning'
  gem.require_paths     = ['lib']
  gem.files             = %w(
    lib/logstash/inputs/courier.rb
  )

  gem.metadata = { 'logstash_plugin' => 'true', 'group' => 'input' }

  gem.add_runtime_dependency 'logstash', '~> 1.4'
  gem.add_runtime_dependency 'log-courier', '= 1.2'
end
