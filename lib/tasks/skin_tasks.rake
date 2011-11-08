namespace :skins do
  desc "Load site skins"
  task(:load_site_skins => :environment) do
    Skin.load_site_css
  end

  def replace_or_new(skin_content)
    skin = Skin.new
    if skin_content.match(/REPLACE:\s*(\d+)/)
      id = $1.to_i
      skin = Skin.where(:id => id).first
      unless skin
        puts "Couldn't find skin with id #{id} to replace"
        return nil
      end
    end
    skin
  end
  
  def set_parents(skin, parent_names)
    # clear existing ones
    skin.skin_parents.delete_all

    parent_position = 1
    parents = parent_names.split(/,\s?/).map {|pn| pn.strip}
    parents.each do |parent_name|
      if parent_name.match(/^(\d+)$/)
        parent_skin = Skin.where("title LIKE 'Archive 2.0: (#{parent_name})%'").first
      else
        parent_skin = Skin.where(:title => parent_name).first
      end
      unless parent_skin
        puts "Couldn't find parent #{parent_name} to add, skipping"
        next
      end
      p = skin.skin_parents.build(:parent_skin => parent_skin, :position => parent_position)
      if !p.valid? && p.errors.full_messages.join(" ").match(/unless replacing/)
        skin.role = "override"
        skin.save or puts "Problem updating skin #{skin.title} to be replacement skin: #{skin.errors.full_messages.join(', ')}"
      else
        p.save or puts "Skipping skin parent #{parent_name}: #{p.errors.full_messages.join(', ')}"
      end
      parent_position += 1
    end    
  end
  
  desc "Load user skins"
  task(:load_user_skins => :environment) do
    dir = Skin.site_skins_dir + 'user_skins_to_load'
    default_preview_filename = "#{dir}/previews/default_preview.png"
    user_skin_files = Dir.entries(dir).select {|f| f.match(/css$/)}
    skins = []
    user_skin_files.each do |skin_file|
      skins << File.read("#{dir}/#{skin_file}").split(/\/\*\s*END SKIN\s*\*\//)
    end
    skins.flatten!
    
    author = User.find_by_login("lim")
    
    skins.each do |skin_content|
      next if skin_content.blank?

      # Determine if we're replacing or creating new
      next unless (skin = replace_or_new(skin_content))

      # set the title and preview
      if skin_content.match(/SKIN:\s*(.*)\s*\*\//)
        title = $1.strip 
        skin.title = title
        if (oldskin = Skin.find_by_title(title)) && oldskin.id != skin.id
          # temporary while testing!
          oldskin.destroy
          # puts "Existing skin with title #{title} - did you mean to replace?"
          # next
        end 
        
        preview_filename = "#{dir}/previews/#{title.gsub(/[^\w\s]+/, '')}.png"
        unless File.exists?(preview_filename)
          puts "No preview filename #{preview_filename} found for #{title}"
          preview_filename = default_preview_filename
        end
        File.open(preview_filename, 'rb') {|preview_file| skin.icon = preview_file}
      else
        puts "No skin title found for skin #{skin_content}"
        next
      end

      # set the css and make public
      skin.css = skin_content
      skin.public = true
      skin.official = true
      skin.do_not_upgrade = false
      skin.author = author unless skin.author

      # make sure we have valid skin now
      if skin.save
        puts "Saved skin #{skin.title}"
      else
        puts "Problem with skin #{skin.title}: #{skin.errors.full_messages.join(', ')}"
        next
      end

      # recache any cached skins
      if skin.cached?
        skin.cache!
      end      
      
      # set parents
      if skin_content.match(/PARENTS:\s*(.*)\s*\*\//)
        parent_string = $1
        set_parents(skin, parent_string)
      end
    end
    
  end
  
  desc "Disable all existing skins"
  task(:disable_all => :environment) do
    default_id = Skin.default.id
    Preference.update_all(:skin_id => default_id)
  end
  
end