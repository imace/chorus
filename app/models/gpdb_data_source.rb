class GpdbDataSource < DataSource
  include SoftDelete
  attr_accessor :db_username, :db_password

  validates_associated :owner_account, :error_field => :instance_account, :unless => proc { |instance| (instance.changes.keys & ['host', 'port', 'db_name']).empty? }

  validates_with DataSourceNameValidator

  has_many :databases, :class_name => 'GpdbDatabase', :dependent => :destroy, :foreign_key => "data_source_id"
  has_many :schemas, :through => :databases, :class_name => 'GpdbSchema'
  has_many :datasets, :through => :schemas
  has_many :workspaces, :through => :schemas, :foreign_key => 'sandbox_id'

  before_validation :build_instance_account_for_owner, :on => :create
  after_update :solr_reindex_later, :if => :shared_changed?
  after_create :create_instance_created_event, :if => :current_user
  after_update :create_instance_name_changed_event, :if => :current_user

  attr_accessor :highlighted_attributes, :search_result_notes
  searchable_model do
    text :name, :stored => true, :boost => SOLR_PRIMARY_FIELD_BOOST
    text :description, :stored => true, :boost => SOLR_SECONDARY_FIELD_BOOST
  end

  def self.reindex_instance instance_id
    instance = GpdbDataSource.find(instance_id)
    instance.solr_index
    instance.datasets(:reload => true).each(&:solr_index)
  end

  def self.create_for_user(user, data_source_hash)
    data_source = user.gpdb_data_sources.create!(data_source_hash, :as => :create)
    QC.enqueue_if_not_queued("GpdbDataSource.refresh", data_source.id, 'new' => true)
    data_source
  end

  def solr_reindex_later
    QC.enqueue_if_not_queued('GpdbDataSource.reindex_instance', id)
  end

  def self.owned_by(user)
    if user.admin?
      scoped
    else
      where(:owner_id => user.id)
    end
  end

  def used_by_workspaces(viewing_user)
    workspaces.workspaces_for(viewing_user).order("lower(workspaces.name)")
  end

  def accessible_to(user)
    GpdbDataSource.accessible_to(user).include?(self)
  end

  def connect_with(account, options = {})
    params = {
        :username => account.db_username,
        :password => account.db_password,
        :host => host,
        :port => port,
        :database => db_name,
        :logger => Rails.logger
    }.merge(options)

    connection = GreenplumConnection.new params

    if block_given?
      connection.with_connection do
        yield connection
      end
    else
      connection
    end
  end

  def refresh_databases(options ={})
    found_databases = []
    rows = connect_with(owner_account).prepare_and_execute_statement(database_and_role_sql).hashes
    database_account_groups = rows.inject({}) do |groups, row|
      groups[row["database_name"]] ||= []
      groups[row["database_name"]] << row["db_username"]
      groups
    end

    database_account_groups.each do |database_name, db_usernames|
      database = databases.find_or_initialize_by_name(database_name)

      if database.invalid?
        databases.delete(database)
        next
      end

      database.update_attributes!({:stale_at => nil}, :without_protection => true)
      database_accounts = accounts.where(:db_username => db_usernames)
      if database.instance_accounts.sort != database_accounts.sort
        database.instance_accounts = database_accounts
        QC.enqueue_if_not_queued("GpdbDatabase.reindex_dataset_permissions", database.id) if database.datasets.count > 0
      end
      found_databases << database
    end
  rescue ActiveRecord::JDBCError => e
    Chorus.log_error "Could not refresh database: #{e.message} on #{e.backtrace[0]}"
  ensure
    if options[:mark_stale]
      (databases.not_stale - found_databases).each do |database|
        database.mark_stale!
      end
    end
  end

  def create_database(name, current_user)
    new_db = databases.build(:name => name)
    raise ActiveRecord::RecordInvalid.new(new_db) unless new_db.valid?

    connect_as(current_user).create_database(name)
    refresh_databases
    databases.find_by_name!(name)
  end

  def account_names
    accounts.pluck(:db_username)
  end

  def refresh_schemas(options={})
    databases.each do |database|
      begin
        Schema.refresh(owner_account, database, options.reverse_merge(:refresh_all => true))
      rescue GreenplumConnection::DatabaseError => e
        Chorus.log_error "Could not refresh database #{database.name}: #{e.message} #{e.backtrace.to_s}"
      end
    end
  end

  def entity_type_name
    'gpdb_data_source'
  end

  def instance_provider
    "Greenplum Database"
  end

  def self.type_name
    'Instance'
  end

  private

  def database_and_role_sql
    roles = Arel::Table.new("pg_catalog.pg_roles", :as => "r")
    databases = Arel::Table.new("pg_catalog.pg_database", :as => "d")

    roles.join(databases).
        on(Arel.sql("has_database_privilege(r.oid, d.oid, 'CONNECT')")).
        where(
        databases[:datname].not_eq("postgres").
            and(databases[:datistemplate].eq(false)).
            and(databases[:datallowconn].eq(true)).
            and(roles[:rolname].in(account_names))
    ).project(
        roles[:rolname].as("db_username"),
        databases[:datname].as("database_name")
    ).to_sql
  end

  def build_instance_account_for_owner
    build_owner_account(:owner => owner, :db_username => db_username, :db_password => db_password)
  end

  def create_instance_name_changed_event
    if name_changed?
      Events::GreenplumInstanceChangedName.by(current_user).add(
          :gpdb_data_source => self,
          :old_name => name_was,
          :new_name => name
      )
    end
  end
end
