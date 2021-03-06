class SearchController < ApplicationController
  
  before_filter :permission_to_search, :only => :index
  
  def index
    @search_terms = params[:q]
    
    unless @search_terms.blank?
      @comments = Comment.search @search_terms,
        :retry_stale => true, :order => 'created_at DESC',
        :with => { :project_id => project_ids },
        :page => params[:page]
    end
  end
  
  protected
  
    def permission_to_search
      unless user_can_search? or (@current_project and project_owner.can_search?)
        flash[:notice] = "Search is disabled"
        redirect_to root_path
      end
    end
    
    def user_can_search?
      current_user.can_search?
    end
    
    def project_owner
      @current_project.user
    end
  
    def project_ids
      if @current_project
        @current_project.id
      else
        current_user.projects.collect { |p| p.id }
      end
    end

end
