#!/usr/bin/env ruby

require 'colorize'
require 'faraday'
require 'faraday_middleware'
require 'optparse'
require 'pathname'
require 'puppet_forge'
require 'puppet_forge/util'

# Doco goes here
module PFCheck
  # Doco goes here
  class Puppetfile
    attr_reader :creds
    attr_reader :forge
    attr_reader :modules

    def initialize(puppetfile = nil, creds = nil)
      @puppetfile = puppetfile || 'Puppetfile'
      @creds = creds
      @modules = []
      @managed_content = {}
      @forge = 'forgeapi.puppetlabs.com'
    end

    def load
      raise 'Puppetfile missing or unreadable' unless File.readable? @puppetfile
      raise 'Missing username or passwd' unless @creds[:user] && @creds[:pass]
      load!
    end

    def load!
      dsl = PFCheck::Puppetfile::DSL.new(self)
      dsl.instance_eval(puppetfile_contents, @puppetfile)
      validate_no_duplicate_names(@modules)
    end

    def validate_no_duplicate_names(modules)
      dupes = modules
              .group_by(&:name)
              .select { |_, v| v.size > 1 }
              .map(&:first)
      msg = format('%<first>s %<second>s %<third>s}',
                   first: 'Puppetfiles cannot contain duplicate module names.',
                   second: 'Remove the duplicates of the following modules:',
                   third: dupes.join(' '))
      raise StandardError, msg unless dupes.empty?
    end

    def define_forge(forge)
      @forge = forge
    end

    def add_module(name, args, creds)
      puts "Checking #{name} for dependencies..."
      mod = PFCheck::Module.new(name, args, creds)
      @modules << mod
    end

    private

    def puppetfile_contents
      File.read(@puppetfile)
    end

    # Doco goes here
    class DSL
      def initialize(librarian)
        @librarian = librarian
      end

      def mod(name, args = nil)
        @librarian.add_module(name, args, @librarian.creds)
      end

      def forge(location)
        @librarian.define_forge(location)
      end
    end
  end

  # Doco goes here
  class Module
    def self.register(klass)
      @klasses ||= []
      @klasses << klass
    end

    def self.new(name, args, creds)
      implementation = @klasses.find do |klass|
        klass.implement?(name, args, creds)
      end
      msg = format('No implementation for Module %<name>s with args %<args>s',
                   name: name,
                   args: args.inspect)
      raise msg unless implementation
      implementation.new(name, args, creds)
    end

    # Doco goes here
    class Base
      attr_reader :deps
      attr_reader :name
      attr_reader :owner
      attr_reader :title

      def initialize(title, args, _creds)
        @title   = title
        @args    = args
        @owner, @name = parse_title(@title)
      end

      private

      def parse_title(title)
        if (match = title.match(/\A(\w+)\Z/))
          [nil, match[1]]
        elsif (match = title.match(/\A(\w+)-(\w+)\Z/))
          [match[1], match[2]]
        else
          msg = format('Module name %<title>s must match', title: title)
          msg += " either 'modulename' or 'owner-modulename'"
          raise ArgumentError, msg
        end
      end
    end

    # Doco goes here
    class Forge < PFCheck::Module::Base
      PFCheck::Module.register(self)

      def self.implement?(name, args, _creds)
        name =~ %r{\w+[/-]\w+} && valid_version?(args)
      end

      def self.valid_version?(expected_version)
        true if expected_version == :latest ||
                expected_version.nil? ||
                PuppetForge::Util.version_valid?(expected_version)
      end

      def initialize(title, expected_version, _creds)
        super
        @versioned_name = "#{title}-#{expected_version}"
        mod = PuppetForge::V3::Release.find(@versioned_name)
        @deps = find_deps(mod)
      rescue Faraday::ClientError => e
        warn "Error finding forge module #{@versioned_name}: #{e}"
        exit(1)
      end

      private

      def find_deps(mod)
        if mod.metadata.key?(:dependencies) &&
           !mod.metadata[:dependencies].empty?
          deps = []
          mod.metadata[:dependencies].each do |x|
            deps << [x[:name], x[:version_requirement]]
          end
        else
          deps = ["No dependencies found for \"#{@versioned_name}\""]
        end
        deps
      end

      # Override the base #parse_title to ensure we have a fully qualified name
      def parse_title(title)
        msg = "Forge module names must match 'owner-modulename'. Got #{title}"
        raise ArgumentError, msg unless (match = title.match(/\A(\w+)-(\w+)\Z/))
        [match[1], match[2]]
      end
    end

    # Doco goes here
    class Git < PFCheck::Module::Base
      PFCheck::Module.register(self)

      def self.implement?(_name, args, _creds)
        false unless args.is_a?(Hash) && args.key?(:git)
        true
      end

      attr_reader :deps
      attr_reader :ref
      attr_reader :url

      def initialize(title, args, creds)
        super
        @auth = { auth: needs_auth?(@args[:git]),
                  user: creds[:user],
                  pass: creds[:pass] }
        @url = munge_remote(@args[:git])
        parse_options(@args)
        @deps = PFCheck::Metadata.new(title, @url, @ref, @auth).deps
      end

      private

      def munge_remote(url)
        # Rewrite SSH URLs to HTTPS
        if @auth[:auth]
          url.sub!(/^([\w-]+:)?([\w-]+@)?/, '').sub!(/([\w,]+):/, '\1/')
          url.insert(0, 'https://')
        end
        # For raw pages, the .git at the end breaks github's redirection
        url.sub(/\.git$/, '')
      end

      def needs_auth?(url)
        url =~ /^([\w-]+:)?([\w-]+@)/
      end

      def parse_options(options)
        ref_opts = %i[branch tag commit ref]
        known_opts = %i[git default_branch] + ref_opts
        unhandled = options.keys - known_opts
        msg = format('Unhandled options %<opts>s specified', opts: unhandled)
        msg += " for #{@name}"
        raise ArgumentError, msg unless unhandled.empty?
        @ref = ref_opts.find do |key|
          break options[key] if options.key?(key)
        end || 'master'
      end
    end
  end

  # Doco goes here
  class Secret
    def initialize(secret_value)
      (class << self; self; end).class_eval do
        define_method(:value) { secret_value }
      end
    end

    def to_s
      '<secret>'
    end

    alias inspect to_s

    def value; end
  end

  # Doco goes here
  class Metadata
    attr_reader :deps

    def initialize(title, url, ref, auth)
      @auth = auth
      @ref = ref
      @title = title
      rawjson = connect(url, "raw/#{ref}/metadata.json")
      rawyaml = connect(url, "raw/#{ref}/.fixtures.yml") unless rawjson
      @deps = find_deps(rawjson, rawyaml)
    end

    private

    def connect(url, path)
      conn = Faraday.new(url: url) do |x|
        x.request :url_encoded
        x.basic_auth(@auth[:user].value, @auth[:pass].value) if @auth[:auth]
        x.use FaradayMiddleware::FollowRedirects
        x.use Faraday::Response::RaiseError
        x.adapter Faraday.default_adapter
      end
      conn.get(path).body
    rescue Faraday::ClientError
      nil
    end

    def find_deps(json, yaml)
      if json
        parse_metadata(json)
      elsif yaml
        parse_fixtures(yaml)
      else
        ["No dependencies found for #{@title} at ref: #{@ref}"]
      end
    end

    def parse_metadata(data)
      raw = JSON.parse(data)
      if !raw.key?('dependencies') || raw['dependencies'].empty?
        return ["No dependencies found for #{@title} at ref: #{@ref}"]
      end
      deps = []
      raw['dependencies'].each do |x|
        deps << [x['name'], x['version_requirement']]
      end
      deps
    end

    def parse_fixtures(data)
      raw = YAML.safe_load(data)
      unless raw['fixtures']['forge_modules']
        return ["No dependencies found for #{@title} at ref: #{@ref}"]
      end
      deps = []
      raw['fixtures']['forge_modules'].each do |_k, v|
        deps << [v['repo'], v['ref']]
      end
      deps
    end
  end
end

# DEBUG
require 'pp'
opts = {}
options = OptionParser.new do |x|
  x.banner = "Usage: #{$PROGRAM_NAME} [-c FILE] [-p FILE]"
  opts[:credfile] = File.expand_path('options', __dir__)
  opts[:puppetfile] = File.expand_path('Puppetfile', __dir__)
  x.on('-c', '--credentials-file FILE',
       "Defaults to 'options' in this script's directory") do |i|
    opts[:credfile] = i
  end
  x.on('-p', '--puppetfile FILE',
       "Defaults to 'Puppetfile' in this script's directory") do |i|
    opts[:puppetfile] = i
  end
  # optionparser sees the 'no-' and magically makes i false when true is desired
  x.on('--no-color', 'Disables colored output') { |i| opts[:nocolor] = !i }
end

begin
  options.parse!
  opts[:credfile] = File.expand_path(opts[:credfile])
  opts[:puppetfile] = File.expand_path(opts[:puppetfile])
  %i[credfile puppetfile].select do |opt|
    unless File.readable?(opts[opt])
      raise "#{opts[opt]} is missing or unreadable"
    end
  end
  File.foreach(opts[:credfile]) do |x|
    if x =~ /^user:/
      opts[:user] = PFCheck::Secret.new(x.sub(/^user:\s+/, '').strip)
    elsif x =~ /^pass:/
      opts[:pass] = PFCheck::Secret.new(x.sub(/^pass:\s+/, '').strip)
    end
  end
  %i[user pass].select do |opt|
    raise "#{opt} not found" if opts[opt].nil?
  end
rescue OptionParser::MissingArgument, OptionParser::InvalidOption => e
  warn e
  exit(1)
rescue RuntimeError => e
  warn e
  exit(1)
end

String.disable_colorization = true if opts[:nocolor]

creds = { user: opts[:user],
          pass: opts[:pass] }

pf = PFCheck::Puppetfile.new(opts[:puppetfile], creds)
pf.load

# Print output with some padding
len = pf.modules.map(&:title).max_by(&:length).length + 5

pf.modules.each do |x|
  msg = ''
  titlelen = x.title.length
  print x.title.blue.bold
  if x.deps
    if x.deps.count == 1 && x.deps[0].is_a?(String)
      msg += format("%#{len - titlelen}<space>s %<deps>s",
                    space: '', deps: x.deps[0]).green
    else
      x.deps.each_with_index do |v, i|
        msg += if i.zero?
                 format("%#{len - titlelen}<space>s %<deps>s",
                        space: '', deps: v.join(' ')).cyan
               else
                 format("\n%#{len}<space>s %<deps>s",
                        space: '', deps: v.join(' '))
               end
      end
      msg = msg.chomp.cyan
    end
    puts msg
  end
  print "-------------------------------------------------\n"
end

# vim: set tw=80 ts=2 sw=2 sts=2 et:
