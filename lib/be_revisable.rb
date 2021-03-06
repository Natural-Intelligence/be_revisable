require 'active_record'
require 'active_support'
require 'amoeba'
module BeRevisable

  def self.table_name_prefix
    'be_revisable_'
  end

  models_dir = Gem::Specification.find_by_name("be_revisable").gem_dir + '/app/models'
  require models_dir + '/be_revisable/revision_set'
  require models_dir + '/be_revisable/revision_info'
  require models_dir + '/be_revisable/revision_change'

  require 'be_revisable/revisable'
  require 'be_revisable/helper'
  require 'be_revisable/act_as_be_revisable'
  require 'be_revisable/deprecatable'
  require 'be_revisable/logable'
  require 'be_revisable/revision_retroactive_change_notifier'
  require 'be_revisable/autoload'

  require 'be_revisable/railtie' if defined?(Rails)
  require 'be_revisable/engine' if defined?(Rails)


  extend Autoload

end