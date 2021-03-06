require 'bigbluebutton_api'

class Bigbluebutton::RoomsController < ApplicationController
  include BigbluebuttonRails::InternalControllerMethods

  before_filter :find_room, :except => [:index, :create, :new, :auth]

  # set headers only in actions that might trigger api calls
  before_filter :set_request_headers, :only => [:join_mobile, :end, :running, :join, :destroy, :auth]

  respond_to :html, :except => :running
  respond_to :json, :only => [:running, :show, :new, :index, :create, :update]

  def index
    respond_with(@rooms = BigbluebuttonRoom.all)
  end

  def show
    respond_with(@room)
  end

  def new
    respond_with(@room = BigbluebuttonRoom.new)
  end

  def edit
    respond_with(@room)
  end

  def create
    @room = BigbluebuttonRoom.new(room_params)

    if params[:bigbluebutton_room] and
        (not params[:bigbluebutton_room].has_key?(:meetingid) or
         params[:bigbluebutton_room][:meetingid].blank?)
      @room.meetingid = @room.name
    end

    respond_with @room do |format|
      if @room.save
        message = t('bigbluebutton_rails.rooms.notice.create.success')
        format.html {
          redirect_to_using_params bigbluebutton_room_path(@room), :notice => message
        }
        format.json {
          render :json => { :message => message }, :status => :created
        }
      else
        format.html {
          message = t('bigbluebutton_rails.rooms.notice.create.failure')
          redirect_to_params_or_render :new, :error => message
        }
        format.json { render :json => @room.errors.full_messages, :status => :unprocessable_entity }
      end
    end
  end

  def update
    respond_with @room do |format|
      if @room.update_attributes(room_params)
        message = t('bigbluebutton_rails.rooms.notice.update.success')
        format.html {
          redirect_to_using_params bigbluebutton_room_path(@room), :notice => message
        }
        format.json { render :json => { :message => message } }
      else
        format.html {
          message = t('bigbluebutton_rails.rooms.notice.update.failure')
          redirect_to_params_or_render :edit, :error => message
        }
        format.json { render :json => @room.errors.full_messages, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    error = false
    begin
      @room.fetch_is_running?
      @room.send_end if @room.is_running?
      message = t('bigbluebutton_rails.rooms.notice.destroy.success')
    rescue BigBlueButton::BigBlueButtonException => e
      error = true
      message = t('bigbluebutton_rails.rooms.notice.destroy.success_with_bbb_error', :error => e.to_s[0..200])
    end

    # TODO: what if it fails?
    @room.destroy

    respond_with do |format|
      format.html {
        flash[:error] = message if error
        redirect_to_using_params bigbluebutton_rooms_url
      }
      format.json {
        if error
          render :json => { :message => message }, :status => :error
        else
          render :json => { :message => message }
        end
      }
    end
  end

  # Used by logged users to join rooms.
  def join
    @user_role = bigbluebutton_role(@room)
    if @user_role.nil?
      raise BigbluebuttonRails::RoomAccessDenied.new

    # anonymous users or users with the role :password join through #invite
    elsif bigbluebutton_user.nil? or @user_role == :password
      redirect_to :action => :invite, :mobile => params[:mobile]

    else
      join_internal(bigbluebutton_user.name, @user_role, bigbluebutton_user.id, :join)
    end
  end

  # Used to join private rooms or to invite anonymous users (not logged)
  def invite
    respond_with @room do |format|

      @user_role = bigbluebutton_role(@room)
      if @user_role.nil?
        raise BigbluebuttonRails::RoomAccessDenied.new
      else
        format.html
      end

    end
  end

  # Authenticates an user using name and password passed in the params from #invite
  # Uses params[:id] to get the target room
  def auth
    @room = BigbluebuttonRoom.find_by_param(params[:id]) unless params[:id].blank?
    if @room.nil?
      message = t('bigbluebutton_rails.rooms.errors.auth.wrong_params')
      redirect_to :back, :notice => message
      return
    end

    # gets the user information, given priority to a possible logged user
    name = bigbluebutton_user.nil? ? params[:user][:name] : bigbluebutton_user.name
    id = bigbluebutton_user.nil? ? nil : bigbluebutton_user.id
    # the role: nil means access denied, :password means check the room
    # password, otherwise just use it
    @user_role = bigbluebutton_role(@room)
    if @user_role.nil?
      raise BigbluebuttonRails::RoomAccessDenied.new
    elsif @user_role == :password
      role = @room.user_role(params[:user])
    else
      role = @user_role
    end

    unless role.nil? or name.nil? or name.empty?
      join_internal(name, role, id, :invite)
    else
      flash[:error] = t('bigbluebutton_rails.rooms.errors.auth.failure')
      render :invite, :status => :unauthorized
    end
  end

  def running
    begin
      @room.fetch_is_running?
    rescue BigBlueButton::BigBlueButtonException => e
      flash[:error] = e.to_s[0..200]
      render :json => { :running => "false", :error => "#{e.to_s[0..200]}" }
    else
      render :json => { :running => "#{@room.is_running?}" }
    end
  end

  def end
    error = false
    begin
      @room.fetch_is_running?
      if @room.is_running?
        @room.send_end
        message = t('bigbluebutton_rails.rooms.notice.end.success')
      else
        error = true
        message = t('bigbluebutton_rails.rooms.notice.end.not_running')
      end
    rescue BigBlueButton::BigBlueButtonException => e
      error = true
      message = e.to_s[0..200]
    end

    if error
      respond_with do |format|
        format.html {
          flash[:error] = message
          redirect_to_using_params :back
        }
        format.json { render :json => message, :status => :error }
      end
    else
      respond_with do |format|
        format.html {
          redirect_to_using_params bigbluebutton_room_path(@room), :notice => message
        }
        format.json { render :json => message }
      end
    end

  end

  def join_mobile
    @join_url = join_bigbluebutton_room_url(@room, :mobile => '1')

    # TODO: we can't use the mconf url because the mobile client scanning the qrcode is not
    #   logged. so we are using the full BBB url for now.
    @qrcode_url = @room.join_url(bigbluebutton_user.name, bigbluebutton_role(@room))
    @qrcode_url.gsub!(/^[^:]*:\/\//i, "bigbluebutton://")
  end

  def fetch_recordings
    error = false

    if @room.server.nil?
      error = true
      message = t('bigbluebutton_rails.rooms.error.fetch_recordings.no_server')
    else
      begin
        # filter only recordings created by this room
        filter = { :meetingID => @room.meetingid }
        @room.server.fetch_recordings(filter)
        message = t('bigbluebutton_rails.rooms.notice.fetch_recordings.success')
      rescue BigBlueButton::BigBlueButtonException => e
        error = true
        message = e.to_s[0..200]
      end
    end

    respond_with do |format|
      format.html {
        flash[error ? :error : :notice] = message
        redirect_to_using_params bigbluebutton_room_path(@room)
      }
      format.json {
        if error
          render :json => { :message => message }, :status => :error
        else
          render :json => true, :status => :ok
        end
      }
    end
  end

  def recordings
    respond_with(@recordings = @room.recordings)
  end

  protected

  def find_room
    @room = BigbluebuttonRoom.find_by_param(params[:id])
  end

  def set_request_headers
    unless @room.nil?
      @room.request_headers["x-forwarded-for"] = request.remote_ip
    end
  end

  def join_internal(username, role, id, wait_action)
    begin
      # first check if we have to create the room and if the user can do it
      unless @room.fetch_is_running?
        if bigbluebutton_can_create?(@room, role)
          user_opts = bigbluebutton_create_options(@room)
          @room.create_meeting(bigbluebutton_user, request, user_opts)
        else
          flash[:error] = t('bigbluebutton_rails.rooms.errors.auth.cannot_create')
          render wait_action, :status => :unauthorized
          return
        end
      end

      # gets the token with the configurations for this user/room
      token = @room.fetch_new_token
      options = if token.nil? then {} else { :configToken => token } end

      # room created and running, try to join it
      url = @room.join_url(username, role, nil, options)
      unless url.nil?
        # change the protocol to join with BBB-Android/Mconf-Mobile if set
        if BigbluebuttonRails::value_to_boolean(params[:mobile])
          url.gsub!(/^[^:]*:\/\//i, "bigbluebutton://")
        end

        # enqueue an update in the meetings for later on
        # note: this is the only update that is not in the model, but has to be here
        # because the model doesn't know when a user joined a room
        Resque.enqueue(::BigbluebuttonMeetingUpdater, @room.id, 15.seconds)

        redirect_to url
      else
        flash[:error] = t('bigbluebutton_rails.rooms.errors.auth.not_running')
        render wait_action
      end

    rescue BigBlueButton::BigBlueButtonException => e
      flash[:error] = e.to_s[0..200]
      redirect_to :back
    end

  end

  def room_params
    unless params[:bigbluebutton_room].nil?
      params[:bigbluebutton_room].permit(*room_allowed_params)
    else
      []
    end
  end

  def room_allowed_params
    [ :name, :server_id, :meetingid, :attendee_password, :moderator_password, :welcome_msg,
      :private, :logout_url, :dial_number, :voice_bridge, :max_participants, :owner_id,
      :owner_type, :external, :param, :record, :duration, :default_layout,
      :metadata_attributes => [ :id, :name, :content, :_destroy, :owner_id ] ]
  end
end
