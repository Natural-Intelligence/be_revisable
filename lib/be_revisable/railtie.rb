module BeRevisable
  class Railtie < Rails::Railtie
    ActiveSupport.on_load(:active_record) do
      extend ::BeRevisable::ActAsBeRevisable
    end
  end
end