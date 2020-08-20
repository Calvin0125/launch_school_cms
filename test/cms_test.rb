ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def admin_session
    { "rack.session" => { user: "admin"} }
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def test_index_signed_in
    create_document "about.md"
    create_document "changes.txt"

    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:user]

    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
    assert_includes last_response.body, "<button type=\"submit\">Sign Out"
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_index_signed_out
    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<form action=\"/users/signin\" method=\"get\">"
  end

  def test_sign_in_page
    get "/users/signin"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<form action=\"/users/signin\" method=\"post\">"
  end

  def test_sign_in_bad_credentials
    post "/users/signin", username: "user", password: "password"
    assert_equal 422, last_response.status
    assert_nil session[:user]
    assert_includes last_response.body, "Invalid Credentials"
  end

  def test_sign_out
    get "/", {}, admin_session
    assert_includes last_response.body, "Signed in as admin"
 
    post "/users/signout"
    assert_equal 302, last_response.status
    assert_equal "You have been signed out.", session[:message]

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_nil session[:username]
    assert_includes last_response.body, "<form action=\"/users/signin\" method=\"get\">"
  end


  def test_viewing_document
    create_document("history.txt", "1993 - Yukihiro Matsumoto dreams up Ruby.")

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "1993 - Yukihiro Matsumoto dreams up Ruby."
  end

  def test_file_that_doesnt_exist
    get "/invalid_file.txt"
    assert_equal 302, last_response.status
    assert_equal "invalid_file.txt does not exist.", session[:message]
    get "/"
    assert_nil session[:message]
  end

  def test_viewing_markdown
    create_document("about.md", "**programming**")

    get "/about.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<strong>programming</strong>"
  end

  def test_edit_file
    create_document("changes.txt")

    get "/changes.txt/edit", {}, admin_session
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "Edit content of changes.txt"
    assert_includes last_response.body, "</textarea>"

    post "/changes.txt/edit", contents: "new content"
    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_new_file
   get "/new", {}, admin_session
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "Add a new document:"
    assert_includes last_response.body, "<button type=\"submit\">"

    post "/new", filename: "new_file.txt"
    assert_equal 302, last_response.status
    assert_equal "new_file.txt was created.", session[:message] 

    get last_response["Location"]
    assert_includes last_response.body, "new_file.txt"
  end

  def test_empty_file_name
    post "/new", {filename: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "The file must have a name."
  end

  def test_invalid_extension
    post "/new", {filename: "test.rb"}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "The file must end with '.txt' or '.md'."
  end

  def test_delete
    create_document("test_file.txt")

    post "/test_file.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test_file.txt has been deleted.", session[:message]

    get last_response["Location"]
    refute_includes last_response.body, "<a href=\"/test_file.txt\">"
  end

  def test_must_be_signed_in_to_delete
    create_document("test_file.txt")

    post "/test_file.txt/delete"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "Sign in"
  end

  def test_must_be_signed_in_to_edit
    create_document("test.txt")

    post "/test.txt/edit"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "Sign in"
  end

  def test_must_be_signed_in_for_edit_page
    create_document("test.txt")

    get "test.txt/edit"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "Sign in"
  end

  def test_must_be_signed_in_for_new_page
    get "/new"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "Sign in"
  end

  def test_must_be_signed_in_to_create_document
    post "/new", filename: "test.txt"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "Sign in"
  end
end