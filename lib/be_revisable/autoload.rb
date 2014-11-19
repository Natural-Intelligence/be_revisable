module BeRevisable
  module Autoload



    def const_missing(name)
      @missing_constants ||= Set.new
      name = name.to_s

      # Prevent infinite loop
      raise "Failed to fetch #{self.name}::#{name}, maybe the call to be_revisable located after calling to the revision set class." if @missing_constants.include? name
      @missing_constants.add(name)

      begin
        nested_module = try_to_create_nested_module(name)
        return nested_module unless nested_module.nil?

        raise_name_error(name) unless name.to_s.include? 'RevisionSet'

        # load revision model
        "#{self.name}::#{name}".sub("BeRevisable::", '').sub('RevisionSet', '').constantize

        revision_set_class = "::#{self.name}::#{name}".constantize

        @missing_constants.delete(name)

        return revision_set_class
      rescue
        @missing_constants.delete(name)
        raise_name_error(name)
      end
    end


    def raise_name_error(name)
      raise NameError.new("uninitialized constant #{self.name}::#{name}")
    end

    def try_to_create_nested_module(name)
      # Checks if the request is a module, i.e. the revision set class is nested under the module for example BeRevisable::MyModule::MyModelRevisionSet
      begin
        nested_module = "#{self.name}::#{name}".sub("BeRevisable::", '').constantize
        if nested_module.class == Module
          module_under_be_revisable = const_set(name, Module.new)
          module_under_be_revisable.extend Autoload
          @missing_constants.delete(name)
          return module_under_be_revisable
        end
      rescue
      end
      nil
    end

  end
end