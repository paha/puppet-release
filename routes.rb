# routes file for puppet release sinatra application

# A welcome page
get "/" do
  @headline = "Branch configuration:"
  erb :index
end

get "/branches" do
  @headline = "Branch configuration:"
  erb :branch_conf
end

get "/release/notes" do
  @headline = "Release notes:"
  erb :svn_log
end

get "/release/new" do
  @headline = "Create a new release."
  erb :new_release
end

post "/release/new" do
  new_release
  redirect "/branches"
end

get "/tags/list" do
  @headline = "Listing 10 most recent tags:"
  erb :tags_list
end

get "/tags/new" do
  @headline = "Make a new tag."
  erb :tags_new
end

post "/tags/new" do
  make_new_tag
  redirect "/tags/list"
end
