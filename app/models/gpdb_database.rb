class GpdbDatabase < ActiveRecord::Base
  include Stale
  include SoftDelete

  attr_accessible :name

  validates :name,
            :format => /^[^\/?&]*$/,
            :presence => true,
            :uniqueness => { :scope => :data_source_id }

  belongs_to :data_source
  has_many :schemas, :class_name => 'GpdbSchema', :as => :parent, :dependent => :destroy
  has_many :datasets, :through => :schemas
  has_many :data_source_account_permissions, :as => :accessed
  has_many :data_source_accounts, :through => :data_source_account_permissions
  has_many :workfile_execution_locations, :foreign_key => :execution_location_id, :conditions => { :execution_location_type => 'GpdbDatabase' }, :dependent => :destroy

  before_save :mark_schemas_as_stale
  after_destroy { data_source_accounts.clear }
  delegate :account_for_user!, :account_for_user, :accessible_to, :to => :data_source

  DATABASE_NAMES_SQL = <<-SQL
  SELECT
    datname
  FROM
    pg_database
  WHERE
    datallowconn IS TRUE AND datname NOT IN ('postgres', 'template1')
    ORDER BY lower(datname) ASC
  SQL

  def self.refresh(account)
    data_source = account.data_source
    results = []
    data_source.connect_with(account).databases.map do |name|
      next if new(:name => name).invalid?

      db = data_source.databases.find_or_create_by_name!(name)
      results << db
      db.update_attributes!({:stale_at => nil}, :without_protection => true)
    end

    results
  end

  def self.reindex_datasets(database_id)
    GpdbDatabase.find(database_id).datasets.not_stale.find_each do |dataset|
      begin
        dataset.solr_index
      rescue => e
        Chorus.log_error "Error in GpdbDataset.reindex_datasets: #{e.message}"
      end
    end
    Sunspot.commit
  end

  def self.visible_to(*args)
    refresh(*args)
  end

  def self.destroy_databases(data_source_id)
    GpdbDatabase.where(:data_source_id => data_source_id).find_each(&:destroy)
  end

  def create_schema(name, current_user)
    new_schema = GpdbSchema.new(:name => name, :database => self)
    raise ActiveRecord::RecordInvalid.new(new_schema) if new_schema.invalid?

    connect_as(current_user).create_schema(name)
    GpdbSchema.refresh(account_for_user!(current_user), self)
    schemas.find_by_name!(name)
  end

  def find_dataset_in_schema(dataset_name, schema_name)
    schemas.find_by_name(schema_name).datasets.find_by_name(dataset_name)
  end

  def connect_as(user)
    connect_with(data_source.account_for_user!(user))
  end

  def connect_with(account, options = {}, &block)
    data_source.connect_with account, options.merge({:database => name }), &block
  end

  private

  def mark_schemas_as_stale
    schemas.find_each(&:mark_stale!) if stale? && stale_at_changed?
  end
end
