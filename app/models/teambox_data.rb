class TeamboxData < ActiveRecord::Base
  belongs_to :user
  attr_accessor :data
  attr_accessor :ready
  attr_accessor :import_data
  
  serialize :project_ids
  serialize :map_data
  
  concerned_with :serialization
  
  attr_accessible :projects_to_export, :type_name, :import_data
  
  TYPE_LOOKUP = {:import => 0, :export => 1}
  TYPE_CODES = TYPE_LOOKUP.invert
  
  before_validation_on_create :process_data
  after_create :check_ready
  after_update :check_ready
  
  has_attached_file :processed_data,
    :url  => "/exports/:id/:basename.:extension",
    :path => Teambox.config.amazon_s3 ?
      "exports/:id/:filename" :
      ":rails_root/exports/:id/:filename"
      
  validate :check_map
  
  def check_map
    if type_name == :import and map_data
      # All users need to be known to the owner
      users = organizations_to_export.map{|o| o.users + o.users_in_projects }.flatten.compact.map(&:login)
      
      map_data.each do |login,dest_login|
        if !users.include?(dest_login)
          @errors.add "user_map_#{login}", "Not known to user"
        end
      end
    end
  end
  
  def process_data
    if processed_data_file_name.nil? and type_name == :import
      begin
        # store the import in a temporary file, since we don't need it for long
        bytes = @import_data.read
        self.processed_data_file_name = "#{user.name}-import.json"
        File.open("/tmp/#{processed_data_file_name}", 'w') do |f|
          f.write bytes
        end
      rescue Exception => e
        @process_error = e.to_s
        puts @process_error
        self.processed_data_file_name = nil
      end
    end
  end
  
  def check_ready
    return unless processed_at.nil?
    
    if type_name == :import and @ready
      is_processing = true
      Teambox.config.delay_data_processing ? send_later(:do_import) : do_import
    elsif type_name == :export
      is_processing = true
      Teambox.config.delay_data_processing ? send_later(:do_export) : do_export
    end
  end
  
  def do_import
    self.processed_at = Time.now
    begin
      unserialize(@object_maps||{})
      is_processing = false
      save!
    rescue Exception => e
      # Something went wrong?!
    end
    
    FileUtils.rm("/tmp/#{processed_data_file_name}")
    self.processed_data_file_name = nil
    destroy # we don't need this anymore!
  end
  
  def do_export
    self.processed_at = Time.now
    @data = serialize(organizations_to_export, projects_to_export, users_to_export)
    upload =  ActionController::UploadedStringIO.new
    upload.write(@data.to_json)
    upload.seek(0)
    upload.original_path = "#{user.login}-export.json"
    self.processed_data = upload
    is_processing = false
    save!
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
  
  def need_data?
    !is_processing && processed_at.nil?
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
      begin
        File.open("/tmp/#{processed_data_file_name}") do |f|
          @data = ActiveSupport::JSON.decode f.read
        end
      rescue
        nil
      end
    else
      @data
    end
  end
end