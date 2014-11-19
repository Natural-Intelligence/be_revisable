module BeRevisable
  class Helper
    def self.create_revision_set_class_for_model(model_name)
      model_tree = model_name.to_s.split('::')

      module_for_class = ::BeRevisable

      # for models under namespaces - create the namespace under be_revisable
      model_tree[0..-2].each do |module_name|
        module_for_class = module_for_class.const_defined?(module_name) ? (module_for_class.name + '::' + module_name).constantize : module_for_class.const_set(module_name, Module.new)
      end

      model_revision_set_class = Class.new ::BeRevisable::RevisionSet
      module_for_class.const_set((model_tree.last + 'RevisionSet').classify, model_revision_set_class)
    end
  end
end