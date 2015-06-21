module BeRevisable
  class RevisionInfo < ActiveRecord::Base

    module Status
      PRIMARY_DRAFT ||= 'PRIMARY_DRAFT'
      TEMPORARY_DRAFT ||= 'TEMPORARY_DRAFT'
      LATEST_RELEASE ||= 'LATEST_RELEASE'
      EXPIRED ||= 'EXPIRED'
      DEPRECATED ||= 'DEPRECATED'
      DEPRECATING_DRAFT ||= 'DEPRECATING_DRAFT'
      DELETED ||= 'DELETED'
    end

    belongs_to :revision_set
    belongs_to :revision, polymorphic: true
    has_and_belongs_to_many :deprecator_of, :join_table => :be_revisable_info_deprecations, :foreign_key => :deprecator_of_revision_info_id, :association_foreign_key => :deprecated_by_revision_info_id, :class_name => RevisionInfo.name.to_s
    has_and_belongs_to_many :deprecated_by_revisions, :join_table => :be_revisable_info_deprecations, :foreign_key => :deprecated_by_revision_info_id, :association_foreign_key => :deprecator_of_revision_info_id, :class_name => RevisionInfo.name.to_s
    has_many :revision_changes, dependent: :destroy

    scope :temporary_drafts, where('be_revisable_revision_infos.status' => ::BeRevisable::RevisionInfo::Status::TEMPORARY_DRAFT)
    scope :deprecating_drafts, where('be_revisable_revision_infos.status' => ::BeRevisable::RevisionInfo::Status::DEPRECATING_DRAFT)

    validates_presence_of :revision_set, :revision, :revision_type, :status
    validates_inclusion_of :status, :in => Status.constants.collect{ |const| Status.const_get(const)}
    validates_presence_of :deprecated_at, :if => :deprecated?, :message => 'can\'t be blank when deprecated'
    validate :released_before_expired

    after_initialize do
      self.status ||= Status::PRIMARY_DRAFT
    end

    before_save do
      self.revision_set.save! if self.revision_set.new_record?
      self.revision_set_id = self.revision_set.id unless self.revision_set.nil? or self.revision_set_id == self.revision_set.id
      validate_uniqueness_of_primary_draft_and_latest_release! if changed? or new_record?
    end



    amoeba do
      nullify [:status, :expired_at, :released_by, :released_at]
    end

    # @return [Boolean] - true if the status is TEMPORARY_DRAFT false otherwise
    def temporary_draft?
      status == Status::TEMPORARY_DRAFT
    end

    # @return [Boolean] - true if the status is PRIMARY_DRAFT false otherwise
    def primary_draft?
      status == Status::PRIMARY_DRAFT
    end

    # @return [Boolean] - true if status is EXPIRED or LATEST_RELEASE false otherwise
    def released?
      status == Status::EXPIRED || status == Status::LATEST_RELEASE
    end

    # @return [Boolean] - true if status is LATEST_RELEASE false otherwise
    def latest_release?
      status == Status::LATEST_RELEASE
    end

    # @return [Boolean] - true if status is EXPIRED false otherwise
    def expired?
      status == Status::EXPIRED
    end

    # @return [Boolean] - true if status is DEPRECATED false otherwise
    def deprecated?
      status == Status::DEPRECATED
    end

    # @return [Boolean] - true if status is DEPRECATING_DRAFT false otherwise
    def deprecating_draft?
      status == Status::DEPRECATING_DRAFT
    end

    def ongoing?
      expired_at.nil?
    end

    def earliest_release_date
      releases = revision_set.releases
      earliest_release = releases.sort_by(&:released_at).first
      earliest_release.try(:released_at)
    end


    # Set the status to by EXPIRED, and sets the expired_at attribute according to the expiration_datetime param
    #
    # @param [DateTime] expiration_datetime - optional, the time the revision has expired. default is DateTime.now
    # @return [BeRevisable::RevisionInfo] - The revision info
    def set_as_expired(expiration_datetime = DateTime.now)
      self.status = Status::EXPIRED
      self.expired_at = expiration_datetime
      self
    end


    # Set the status to be PRIMARY_DRAFT
    #
    # @return [BeRevisable::RevisionInfo] - The revision info
    def set_as_primary_draft
      self.status = Status::PRIMARY_DRAFT
      self
    end

    # Set the status to be TEMPORARY_DRAFT
    #
    # @return [BeRevisable::RevisionInfo] - The revision info
    def set_as_temporary_draft
      self.status = Status::TEMPORARY_DRAFT
      self
    end

    # Set the status to be DEPRECATING_DRAFT
    #
    # @return [BeRevisable::RevisionInfo] - The revision info
    def set_as_deprecating_draft
      self.status = Status::DEPRECATING_DRAFT
      self
    end


    # Set the status to be LATEST_RELEASE, sets the released_at and released_by attributes according to the params
    #
    # @param [Integer] user_id - the id of the user that released the revision
    # @param [DateTime] expiration_datetime - optional, the time the revision is released. default is DateTime.now
    # @param [Boolean] set_metadata - if true, released_at and released_by will be set. (true by default)
    #
    # @return [BeRevisable::RevisionInfo] - The revision info
    def set_as_latest_release(user_id, release_datetime = DateTime.now, set_metadata = true)
      if set_metadata
        self.released_at= release_datetime
        self.released_by = user_id
      end
      self.expired_at = nil
      self.status = Status::LATEST_RELEASE
      self
    end


    # @return [BeRevisable::RevisionSet] - the revision set, if no such exists builds it.
    def revision_set
      super || build_revision_set
    end


    def self.released_datetime_range
      return nil unless released?
      return released_at..(expired_at || DateTime.now)
    end

    # Return the full list of all revision-infos this revision is deprecating including recursively all revisions that were deprecated by them as well.
    # Ordered from the direct revision being deprecated to the earliest one that was deprecated by this chain.
    def deprecator_of_chain
      deprecation_chain(:deprecator_of)
    end

    # Return the full list of all revision-infos this revision was deprecated by and recursively the revisions that deprecated the rest of those revisions.
    # Ordered from the initial deprecator to the latest deprecator (i.e. the active one)
    def deprecated_by_revisions_chain
      deprecation_chain(:deprecated_by_revisions)
    end

    protected

    # @return [BeRevisable::RevisionSet] - builds a new revision set according to the revision_type
    def build_revision_set
      raise 'can\'t build revision set object without revision' if revision_type.nil?
      revision_set_obj= "BeRevisable::#{revision_type}RevisionSet".constantize.new
      revision_set_obj.revisions.push revision
      self.revision_set = revision_set_obj

    end

    # If the status is PRIMARY_DRAFT or LATEST_RELEASE - raise an exception if there is another revision
    #   info in the revision tree with the same status
    def validate_uniqueness_of_primary_draft_and_latest_release!
      return true unless primary_draft? or latest_release?
      count_qry = RevisionInfo.where(:status => status).where(:revision_set_id => revision_set_id)
      count_qry = count_qry.where('id != ?', id) unless id.nil?
      raise  "#{status} is only allowed once per revision set" if count_qry.exists?
    end

    # Generic method to get a deprecation chain (including recursively all revisions) according to the given method
    # Ordered from the direct revision to the most remote
    def deprecation_chain(method)
      chain = []
      send(method).each do |object|
        chain << object
        chain << object.deprecation_chain(method)
      end
      return chain.flatten.uniq
    end

    private
    def released_before_expired
      return if expired_at.blank?

      if released_at.blank?
        errors.add(:released_at, 'must be set when expired_at is set')
        return
      end

      errors.add(:expired_at, 'must come after released at') if released_at > expired_at
    end

  end
end