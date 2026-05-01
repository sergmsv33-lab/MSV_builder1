# encoding: UTF-8
# Main entry point for MSV Bed Builder.

module MSV
  module BedBuilder
    PATH = File.dirname(__FILE__).freeze
    CORE_PATH = File.join(PATH, 'core').freeze
  end
end

require File.join(MSV::BedBuilder::CORE_PATH, 'MSV_bed_builder_enhanced')
