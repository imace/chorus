class HdfsDataSource < ActiveRecord::Base
  include TaggableBehavior
  include Notable

  attr_accessible :name, :host, :port, :description, :username, :group_list
  belongs_to :owner, :class_name => 'User'
  has_many :activities, :as => :entity
  has_many :events, :through => :activities
  has_many :hdfs_entries
  validates_presence_of :name, :host, :port
  validates_length_of :name, :maximum => 64

  validates_with DataSourceNameValidator

  after_create :create_root_entry

  attr_accessor :highlighted_attributes, :search_result_notes
  searchable_model do
    text :name, :stored => true, :boost => SOLR_PRIMARY_FIELD_BOOST
    text :description, :stored => true, :boost => SOLR_SECONDARY_FIELD_BOOST
  end

  def url
    "gphdfs://#{host}:#{port}/"
  end

  def self.refresh(id)
    find(id).refresh
  end

  def refresh(path = "/")
    entries = HdfsEntry.list(path, self)
    entries.each { |entry| refresh(entry.path) if entry.is_directory? }
  rescue Hdfs::DirectoryNotFoundError => e
    return unless path == '/'
    hdfs_entries.each do |hdfs_entry|
      hdfs_entry.mark_stale!
    end
  end

  def create_root_entry
    hdfs_entries.create({:hdfs_data_source => self, :path => "/", :is_directory => true}, { :without_protection => true })
  end

  def self.type_name
    'Instance'
  end

  def online?
    state == "online"
  end

end