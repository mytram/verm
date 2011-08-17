require 'rubygems'
require 'test/unit'
require 'ruby-debug'

require File.expand_path(File.join(File.dirname(__FILE__), 'net_http_multipart_post'))
require File.expand_path(File.join(File.dirname(__FILE__), 'verm_spawner'))

verm_binary = File.join(File.dirname(__FILE__), '..', 'verm')
verm_data   = File.join(File.dirname(__FILE__), 'data')
mime_types_file = File.join(File.dirname(__FILE__), 'fixtures', 'mime.types')
VERM_SPAWNER = VermSpawner.new(verm_binary, verm_data, mime_types_file)

module Verm
  class TestCase < Test::Unit::TestCase
    undef_method :default_test if instance_methods.include? 'default_test' or
                                  instance_methods.include? :default_test

    def setup
      VERM_SPAWNER.clear_data
      VERM_SPAWNER.start_verm
      VERM_SPAWNER.wait_until_available
    end
  
    def teardown
      VERM_SPAWNER.stop_verm
      VERM_SPAWNER.wait_until_not_available
    end
    
    def timeout
      10 # seconds
    end
    
    def post_file(options)
      orig_filename = File.join(File.dirname(__FILE__), 'fixtures', options[:file])
      file_data = File.read(orig_filename)
      
      request = Net::HTTP::MultipartPost.new(options[:path])
      request.attach 'uploaded_file', file_data, options[:file], options[:type]
      request.form_data = {"test" => "bar"}
      
      http = Net::HTTP.new(VERM_SPAWNER.hostname, VERM_SPAWNER.port)
      http.read_timeout = timeout
      location = http.start do |connection|
        response = connection.request(request)
        response['location']
      end

      dest_filename = File.expand_path(File.join(VERM_SPAWNER.verm_data, location))
      raise "Verm supposedly saved the file to #{dest_filename}, but that doesn't exist" unless File.exist?(dest_filename)
      saved_data = File.read(dest_filename)
      raise "The data saved to verm doesn't match the original! #{saved_data.inspect} vs. #{file_data.inspect}" unless saved_data == file_data
      raise "The data was saved to #{location}, but it was supposed to be saved under #{options[:path]}/" if location[0..options[:path].length] != "#{options[:path]}/"
      raise "The data was saved to #{dest_filename}, but it was supposed to have a #{options[:expected_extension]} extension" if options[:expected_extension] && dest_filename[(-options[:expected_extension].length - 1)..-1] != ".#{options[:expected_extension]}"
      dest_filename
    end
    
    def get(options)
      http = Net::HTTP.new(VERM_SPAWNER.hostname, VERM_SPAWNER.port)
      http.read_timeout = timeout
      
      response = http.get(options[:path], options[:headers])
      
      assert_equal options[:expected_response_code] || 200, response.code.to_i, "The response didn't have the expected code"
      assert_equal options[:expected_content_type], response.content_type, "The response had an incorrect content-type" if options.has_key?(:expected_content_type)
      assert_equal options[:expected_content_length], response.content_length, "The response had an incorrect content-length" if options.has_key?(:expected_content_length)
      assert_equal options[:expected_content_encoding], response['content-encoding'], "The response had an incorrect content-encoding" if options.has_key?(:expected_content_encoding)
      assert_equal options[:expected_content], response.body, "The response had incorrect content" if options.has_key?(:expected_content)
      
      response
    end
  end
end