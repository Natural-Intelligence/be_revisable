module BeRevisable
  ###############################################################################################
  # A class that indents to notify listeners about a retroactive change in a revision.
  ###############################################################################################
  class RevisionRetroactiveChangeNotifier
    # Notifies generically all listeners about a change
    # @param [String] revision_type - A string of the type of the revision that was modified, to be used for notifying the relevant listeners only.
    # @param [Integer] revision_set_id - The Revision-Set ID that the change was done for
    # @param [Array<Integer>] affected_revision_ids - A list of IDs of all revisions that were affected as a result of this change, which should include both deprecated & deprecating IDs
    def self.notify(revision_type, revision_set_id, affected_revision_ids)
      event_name = "#{revision_type}_revision_retroactive_change"
      ActiveSupport::Notifications.instrument(event_name, {:revision_set_id => revision_set_id, :affected_revision_ids => affected_revision_ids})
    end
  end
end
