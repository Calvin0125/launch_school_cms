require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

root = File.expand_path("..", __FILE__)

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_users(root)
  if ENV["RACK_ENV"] == "test"
    path = File.join(root, "/test/users.yml")
    YAML.load_file(path)
  else
    path = File.join(root, "/users.yml")
    YAML.load_file(path)
  end
end

def load_file(path)
  contents = File.read(path)
    
  if path.end_with?(".txt")
    headers["Content-Type"] = "text/plain"
    contents
  elsif path.end_with?(".md")
    erb render_markdown(contents)
  end
end

def validate_user(user)
  return if user
  session[:message] = "You must be signed in to do that."
  redirect "/"
end

def validate_credentials(username, password, root)
  users = load_users(root)
  users.each do |key, value|
    if key == username && BCrypt::Password.new(value) == password
      return username
    end
  end
  return false
end

configure do
  enable :sessions
  set :session_secret, "secret"
end

before do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end
end

get "/" do
  if session[:user]
    @username = session[:user]
    erb :index
  else
    erb :signed_out
  end
end

get "/users/signin" do
  if session[:signed_in]
    redirect "/"
  else
    @username = ""
    @password = ""
    erb :signin
  end
end

post "/users/signin" do
  @username = params[:username]
  @password = params[:password]
  user = validate_credentials(@username, @password, root)
  if user
    session[:user] = user
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid Credentials"
    status 422
    erb :signin
  end
end

post "/users/signout" do
  session[:user] = nil
  session[:message] = "You have been signed out."
  redirect "/"
end

get "/new" do
  validate_user(session[:user])
  erb :new
end

get "/:filename" do
  filename = params[:filename]
  path = File.join(data_path, filename)
  if @files.include?(filename)
    load_file(path)
  else
    session[:message] = "#{filename} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do
  validate_user(session[:user])
  @filename = params[:filename]
  path = File.join(data_path, @filename)
  @contents = File.read(path)
  erb :edit_file
end

post "/:filename/delete" do
  validate_user(session[:user])
  filename = params[:filename]
  path = File.join(data_path, filename)
  File.delete(path)
  session[:message] = "#{filename} has been deleted."
  redirect "/"
end

post "/:filename/edit" do
  validate_user(session[:user])
  @filename = params[:filename]
  path = File.join(data_path, @filename)
  new_contents = params[:contents]
  File.write(path, new_contents)
  session[:message] = "#{@filename} has been updated." 
  redirect "/"
end

post "/new" do
  validate_user(session[:user])
  filename = params[:filename]
  if filename.length == 0
    session[:message] = "The file must have a name."
    status 422
    erb :new
  elsif !(filename.end_with?(".txt") || filename.end_with?(".md"))
    session[:message] = "The file must end with '.txt' or '.md'."
    status 422
    erb :new
  else
    path = File.join(data_path, filename)
    File.new(path, "w")
    session[:message] = "#{filename} was created."
    redirect "/"
  end
end



