require 'active_support/concern'
module BeRevisable
  module Logable
    extend ActiveSupport::Concern

    included do

      scope :revisable_with_changes, lambda { includes(revision_info: :revision_changes) }

      # Log change of user
      def log_change(user_id, description, payload='')
        revision_info.revision_changes.create(user_id: user_id, description: description, payload: payload, change_date: DateTime.current)
      end

      # Retrieve all changes
      def changes
        revision_info.revision_changes
      end

    end
  end
end

