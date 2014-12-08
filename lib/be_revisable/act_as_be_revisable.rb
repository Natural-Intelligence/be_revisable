module BeRevisable
  module ActAsBeRevisable
    def be_revisable(options={}, &block)

      # Creates the ObjectRevisionSet for the revisable model and add an association for it to the revisable model
      # for example, if the revisable model is Site, creates a model named SiteRevisionSet and associate it to Site through RevisionInfo
      model_revision_set_class = ::BeRevisable::Helper.create_revision_set_class_for_model(self.model_name)

      # Create a has many association to the revisable model and overrides the new, create and build methods of the association
      model_revision_set_class.has_many(:revisions,
                                        through: :revision_infos,
                                        source_type: model_name.to_s,
                                        autosave: false,
                                        dependent: :destroy,
                                        inverse_of: "#{self.name.to_s.underscore.gsub('/', '__')}_revision_set".to_sym,
                                        validate: false) do

        def new(attributes = nil, options = {})
          build(attributes, options)
        end

        def create!(attributes = nil, options = {}, &block)
          create_revision(attributes, options, true, &block)
        end

        def create(attributes = nil, options = {}, &block)
          create_revision(attributes, options, false, &block)
        end

        def build(attributes = nil)
          revision = super(attributes)
          revision.revision_set = proxy_association.owner
          revision
        end

        private

        def create_revision(attributes = nil, options = {}, raise_on_error, &block)
          if attributes.is_a?(Array)
            attributes.collect { |attr| create_revision(attr, options, raise_on_error, &block) }
          else
            revision = build(attributes, &block)
            yield(revision) if block_given?
            raise_on_error ? revision.save! : revision.save
            revision
          end
        end
      end

      model_revision_set_class.class_exec &block if block_given?


      include Revisable
      include Deprecatable if options[:deprecatable]

    end
  end

end