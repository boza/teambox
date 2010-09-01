class TeamboxData < ActiveRecord::Base
  belongs_to :user
  attr_accessor :data
  attr_accessor :ready
  
  serialize :project_ids
  serialize :map_data
  
  concerned_with :serialization
  
  attr_accessible :projects_to_export, :type_name, :processed_data
  
  TYPE_LOOKUP = {:import => 0, :export => 1}
  TYPE_CODES = TYPE_LOOKUP.invert
  
  before_validation_on_create :process_data
  
  has_attached_file :processed_data,
    :url  => "/exports/:id/:basename.:extension",
    :path => Teambox.config.amazon_s3 ?
      "exports/:id/:filename" :
      ":rails_root/exports/:id/:filename"
  
  def process_data
    if @ready
      if type_name == :import
        self.processed_at = Time.now
        unserialize(@object_maps)
      else
        self.processed_at = Time.now
        @data = serialize(organizations_to_export, projects_to_export, users_to_export)
        upload =  ActionController::UploadedStringIO.new
        upload.write(@data.to_json)
        upload.seek(0)
        upload.original_path = "#{user.login}-export.json"
        self.processed_data = upload
      end
    else
      if processed_data_file_name.nil? and type_name == :import
        # store the import in a temporary file, since we don't need it for long
        self.processed_data_file_name = "#{user.name}-import.json"
        TempFile.new(processed_data_file_name) do |f|
          f.write serialize(organizations, projects, users).to_json
        end
      end
    end
  end
  
  def type_name
    TYPE_CODES[type_id]
  end
  
  def type_name=(value)
    self.type_id = TYPE_LOOKUP[value.to_sym]
  end
  
  def exported?
    type_name == :export && !processed_at.nil?
  end
  
  def imported?
    type_name == :import && !processed_at.nil?
  end
  
  def projects_to_export=(value)
    self.project_ids = Array(value).map(&:to_i).compact
  end
  
  def projects_to_export
    Project.find(:all, :conditions => {:id => project_ids})
  end
  
  def organizations_to_export
    Organization.find(:all, :conditions => {:projects => {:id => project_ids}}, :joins => [:projects])
  end
  
  def users_to_export
    organizations_to_export.map{|o| o.users + o.users_in_projects }.flatten.compact
  end
  
  def data
    if @data.nil? and type_name == :import
      File.open(processed_data_file_name) do |f|
        @data = ActiveRecord::JSON.decode f.read
      end
    else
      @data
    end
  end
end