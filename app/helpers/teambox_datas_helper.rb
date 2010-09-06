module TeamboxDatasHelper
  def new_teambox_export_link
    link_to content_tag(:span,"Export"), new_teambox_data_path(:type => :export), :class => 'add_button'
  end
  
  def new_teambox_import_link
    link_to content_tag(:span,"Import"), new_teambox_data_path(:type => :import), :class => 'add_button'
  end
  
  def options_for_user_map
    [['Please Select...', '#invalid']] + current_user.users_with_shared_projects.map do |user|
      ["#{user.to_s} (@#{user.login})", user.login]
    end
  end
end