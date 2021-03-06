namespace :users do
  task :unfollowers, [:user_id] => [:environment] do |_, args|
    users = args.user_id ? User.where(id: args.user_id) : User.where("email NOT LIKE 'change@me-%'")

    users.find_each do |user|
      
      begin
        twitter_client = client(user)

        old_followers = user.followers.pluck(:uid)
        new_followers = fetch_followers(twitter_client)
        new_elements, deleted_elements = comparelist(old_followers, new_followers)

        deleted_elements.each do |deleted_uid|
          # move the follower to the unfollowers table
          Follower.where(user_id: user.id, uid: deleted_uid).destroy_all
          unfollower = Unfollower.where(user_id: user.id, uid: deleted_uid).first_or_create

          twitter_user = twitter_client.user(unfollower.uid.to_i)
          unfollower.update_attributes(
            username: twitter_user.screen_name,
            name: twitter_user.name,
            description: twitter_user.description,
            profile_image_url: twitter_user.profile_image_url,
            updated: true
          )
        end

        new_elements.each do |new_uid|
          # move the unfollower to the followers table
          unfollowers = Unfollower.where(user_id: user.id, uid: new_uid)
          follower = Follower.where(user_id: user.id, uid: new_uid).first_or_create

          unless unfollowers.empty?
            unfollowers.destroy_all
            lookup = twitter_client.user(new_uid.to_i)
            follower.update_attributes(username: lookup.screen_name, name: lookup.name, description: lookup.description, profile_image_url: lookup.profile_image_url, updated: true)
          end
        end
      rescue Exception => e
        next
      end
    end
  end

  def client(user)
    twitter_client = Twitter::REST::Client.new do |config|
      config.consumer_key        = ENV.fetch('TW_APP_ID')
      config.consumer_secret     = ENV.fetch('TW_APP_SECRET')
      config.access_token        = user.access_token
      config.access_token_secret = user.access_token_secret
    end
    twitter_client
  end

  def comparelist(old_list, new_list)
    deleted_elements = []
    new_elements = []

    diff = old_list - new_list | new_list - old_list
    diff.each do |d|
      if old_list.include? d
        deleted_elements.push(d)
      else
        new_elements.push(d)
      end
    end
    
    return new_elements, deleted_elements
  end

  def fetch_followers(twitter_client)
    cursor = '-1'
    followers = []
    while cursor != 0 do
      begin
        limited_followers = twitter_client.follower_ids(cursor: cursor)
        limited_followers.attrs[:ids].each do |id|
          followers.push(id.to_s)
        end
        cursor = limited_followers.attrs[:next_cursor]
      rescue Twitter::Error::TooManyRequests => error
        sleep error.rate_limit.reset_in + 1
        retry
      end
    end
    followers
  end
end
