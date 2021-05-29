require 'net/http'
require 'json'
require 'uri'

require_relative 'infermedica/model'
require_relative 'infermedica/conditions'
require_relative 'infermedica/diagnosis'
require_relative 'infermedica/info'
require_relative 'infermedica/lab_tests'
require_relative 'infermedica/risk_factors'
require_relative 'infermedica/symptoms'
require_relative 'infermedica/connection'
require_relative 'infermedica/configuration'

# = Infermedica: A ruby interface to the infermedica REST API
#
# == Quick Start
#
# You will need a valid *api_id* and *api_key*.
# Get one from https://developer.infermedica.com/docs/api
#
# To start using the API, require the infermedica gem and create an
# Infermedica::Api object, passing the api_id and api_key to the constructor
#
# The constructor takes a hash as argument, so you have different options
# to pass the id and key:
#
#    require 'infermedica'
#    api = Infermedica::Api.new(api_id: 'xxxxx', api_key: 'xxxxxxxxxxx')
#
# or put the key and id in a .yaml file, read it and pass the resulting hash
#
# In config.yaml
#    :api:id:  xxxxx
#    :api_key: xxxxxxxxxxx
#
# In your script
#
#    require 'infermedica'
#    require 'yaml'
#    access = YAML.load(File.read('./config.yaml'))
#    api = Infermedica::Api.new(access)
#
# Also can configure the gem
#
#    Infermedica.configure do |config|
#      config.api_id = 'xxxxxx'
#      config.api_key = 'xxxxxxxxxx'
#    end
#
# and then you can safely use the api helper method
#
#    infermedica = Infermedica.api(model: 'my-model')
#    infermedica.get_conditions

module Infermedica

  # Exceptions

  # HTTP error raised when we don't get the expected result from an API call
  class HttpError < StandardError; end

  # Missing field or field not set in a request
  class MissingField < StandardError; end

  # Configuration instance
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Configure gem through block parameters
  def self.configure
    yield(configuration)
  end

  # Api helper method
  def self.api(**args)
    default_options = {
      api_id: self.configuration.api_id,
      api_key: self.configuration.api_key
    }
    Api.new(default_options.merge(**args))
  end

  # Api defines all operations available from the REST API

  class Api

    def get_conditions(args = {}) # return a Hash of known conditions
      get_collection("/conditions?#{URI.encode_www_form(args)}")
    end

    def get_condition(id) # return a Condition object
      response = @connection.get("/conditions/#{id}")
      return Condition.new(response)
    end

    def get_lab_tests # erturn a Hash of lab_tests
      get_collection('/lab_tests')
    end

    def get_lab_test(id) # return a LabTest object
      response = @connection.get("/lab_tests/#{id}")
      return LabTest.new(response)
    end

    def get_risk_factors(args = {}) # return a Hash of risk_factors
      get_collection("/risk_factors?#{URI.encode_www_form(args)}")
    end

    def get_covid_risk_factors # return a Hash of risk_factors
      get_collection('/covid19/risk_factors')
    end

    def get_risk_factor(id, args = {}) # return a RiskFactor object
      response = @connection.get("/risk_factors/#{id}?#{URI.encode_www_form(args)}")
      return RiskFactor.new(response)
    end

    def get_symptoms(args = {}) # return a list of symptoms
      get_collection("/symptoms?#{URI.encode_www_form(args)}")
    end

    def get_covid_symptoms # return a list of symptoms
      get_collection('/covid19/symptoms')
    end

    def get_symptom(id, args = {}) # return a Symptom object
      response = @connection.get("/symptoms/#{id}?#{URI.encode_www_form(args)}")
      return Symptom.new(response)
    end

    # Get the Api info (version, date,
    # number of conditions, lab_tests, risk_factors, symptoms

    def get_info
      response = @connection.get("/info")
      return Info.new(response)
    end

    # Submit a diagnosis object to get a diagnosis, or a list of additional
    # conditions required to refine the diagnosis
    # See examples/diagnosis.rb for an example
    def diagnosis(diag)
      response = @connection.post('/diagnosis', diag.to_json)
    end

    def covid19_diagnosis(diag)
      diag.age = diag.age[:value]
      response = @connection.post('/covid19/diagnosis', diag.to_json)
    end

    # Submit a diagnosis object to get a triage
    # See examples/triage.rb for an example
    def triage(diag)
      response = @connection.post('/triage', diag.to_json)
    end

    def covid19_triage(diag)
      diag.age = diag.age[:value]
      response = @connection.post('/covid19/triage', diag.to_json)
    end

    # Submit a diagnosis object to get an explanation
    # See examples/explain.rb for an example
    def explain(req, args = {})
      raise Infermedica::MissingField, 'target must be set' if req.target.nil?
      response = @connection.post('/explain', req.to_json, args)
    end

    # Submit a search request, possibly filtered by where to look
    # See examples/search.rb for an example

    def search(phrase, args = {})
      url = '/search?phrase=' + phrase
      args['max_results'] = 8 unless args.key?('max_results')
      response = @connection.get("#{url}&#{URI.encode_www_form(args)}")
    end

    # Submit symptoms and to get the related symptoms
    def related_symptoms(symptoms)
      response = @connection.post('/suggest', symptoms.to_json)
    end

    # Create a new Infermedica::Api object.
    # Takes a hash as argument.
    # The *api_id* and *api_key* entries are required.

    def initialize(args)
      raise ArgumentError,
      'Infermedica::Api::initialize argument needs to be a Hash)' unless
        args.is_a?(Hash)
      raise ArgumentError, 'api_id is required' unless args.key?(:api_id)
      raise ArgumentError, 'api_key is required' unless args.key?(:api_key)

      connection_args = { api_id: args[:api_id], api_key: args[:api_key] }
      connection_args[:endpoint] = args[:endpoint] if args.key?(:endpoint)
      connection_args[:model] = args[:model] if args.key?(:model)
      connection_args[:interview_id] = args[:interview_id].to_s if args.key?(:interview_id)
      @connection = Connection.new(connection_args)

      # Probably need more argument validation here...
      args.each do |k, v|
        instance_variable_set(:"@#{k}", v)
      end
    end

    private

    # Common frontend to the public methods that require collections

    def get_collection(path) # :nodoc:
      response = @connection.get(path)
      # response is an array
      collection = {}
      response.each do |item|
        collection[item['id']] = item
      end
      collection
    end
  end # class Api
end # module
