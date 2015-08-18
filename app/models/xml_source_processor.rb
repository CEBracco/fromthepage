module XmlSourceProcessor

  @text_dirty = false
  @translation_dirty = false

  def source_text=(text)
    @text_dirty = true
    super
  end
  
  def source_translation=(translation)
    @translation_dirty = true
    super    
  end

  def validate
#    valid = super
#    debug("validate valid=#{valid}")
    if @text_dirty && !validate_source
#      valid = false
    end
#    debug("validate valid=#{valid}")
    debug("validate errors=#{errors.count}")
  end

  def validate_source
    debug('validate_source')
    if self.source_text.blank?
      return
    end
    # split on all begin-braces
    tags = self.source_text.split('[[')
    # remove the initial string which occurs before the first tag
    debug("validate_source: tags to process are #{tags.inspect}")
    tags = tags - [tags[0]]
    debug("validate_source: massaged tags to process are #{tags.inspect}")
    for tag in tags
      debug(tag)
      unless tag.include?(']]')
        errors.add_to_base("Mismatched braces: no closing braces after \"[[#{tag}\"!")
      end
      # just pull the pieces between the braces
      inner_tag = tag.split(']]')[0]
      if inner_tag =~ /^\s*$/
        errors.add_to_base("Error: Blank tag in \"[[#{tag}\"!")
      end
      # check for blank title or display name with pipes
      if inner_tag.include?("|")
        tag_parts = inner_tag.split('|')
        debug("validate_source: inner tag parts are #{tag_parts.inspect}")
        if tag_parts[0] =~ /^\s*$/
          errors.add_to_base("Error: Blank target in \"[[#{inner_tag}]]\"!")
        end
        if tag_parts[1] =~ /^\s*$/
          errors.add_to_base("Error: Blank display in \"[[#{inner_tag}]]\"!")
        end
      end
    end
#    return errors.size > 0
  end

  ##############################################
  # All code to convert transcriptions from source
  # format to canonical xml format belongs here.
  #
  #
  ##############################################
  def process_source
    if @text_dirty
      self.xml_text = wiki_to_xml(self.source_text)
    end

    if @translation_dirty
      self.xml_translation = wiki_to_xml(self.source_translation, PAGE::TEXT_TYPE::TRANSLATION)      
    end
  end

  def wiki_to_xml(wiki, text_type=Page::TEXT_TYPE::TRANSCRIPTION)
    xml_string = wiki || ""

    xml_string = process_square_braces(xml_string)
    xml_string = process_line_breaks(xml_string)
    xml_string = valid_xml_from_source(xml_string)
    xml_string = update_links_and_xml(xml_string, false, text_type)

    xml_string    
  end


  def generate_preview
    xml_string = wiki_to_xml(self.source_text)
    xml_string = update_links_and_xml(xml_string, true)
    return xml_string
  end


  
  BRACE_REGEX = /\[\[.*?\]\]/m
  def process_square_braces(text)
    # find all the links
    wikilinks = text.scan(BRACE_REGEX)
    
    wikilinks.each do |wikilink_contents|
      # strip braces
      munged = wikilink_contents.sub('[[','')
      munged = munged.sub(']]','')
            
      # extract the title and display
      if munged.include? '|'
        parts = munged.split '|'
        title = parts[0]
        verbatim = parts[1]
      else
        title = munged
        verbatim = munged
      end
      title = canonicalize_title(title)
      
      replacement = "<link target_title=\"#{title}\">#{verbatim}</link>"
      
      text.sub!(wikilink_contents, replacement)      
    end
    
    text
  end


  def canonicalize_title(title)
    # kill all tags
    title = title.gsub(/<.*?>/, '')
    # linebreaks -> spaces
    title = title.gsub(/\n/, ' ')
    # multiple spaces -> single spaces
    title = title.gsub(/\s+/, ' ')

    title
  end

  # transformations converting source mode transcription to xml
  def process_line_breaks(text)
    text="<p>#{text}</p>"
    text = text.gsub(/\n\s*\n/, "</p><p>")
    text = text.gsub(/\r\n/, "<lb/>")
    text = text.gsub(/\n/, "<lb/>")
    text = text.gsub(/\r/, "<lb/>")
    return text
  end

  def valid_xml_from_source(source)
    source = source || ""
    safe = source.gsub /\&/, '&amp;'
    safe.gsub! /\&amp;amp;/, '&amp;'

    string = <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
      <page>
        #{safe}
      </page>
EOF
  end

  def update_links_and_xml(xml_string, preview_mode=false, text_type=Page::TEXT_TYPE::TRANSCRIPTION)
    # first clear out the existing links
    clear_links(text_type)
    processed = ""
    # process it
    doc = REXML::Document.new xml_string

    doc.elements.each("//link") do |element|
      # default the title to the text if it's not specified
      if !(title=element.attributes['target_title'])
        title = element.text
      end

      #display_text = element.text
      display_text = ""
      element.children.each do |e|
        display_text += e.to_s
      end
      debug("link display_text = #{display_text}")
      # create new blank articles if they don't exist already

      if !article = collection.articles.where(:title => title).first
        article = Article.new
        article.title = title
        article.collection = collection
        article.save! unless preview_mode
      end
      link_id = create_link(article, display_text, text_type) unless preview_mode
      # now update the attribute
      link_element = REXML::Element.new("link")
      element.children.each { |c| link_element.add(c) }
      link_element.add_attribute('target_title', title)
      debug("element="+link_element.inspect)
      debug("article="+article.inspect)
      link_element.add_attribute('target_id', article.id.to_s) unless preview_mode
      link_element.add_attribute('link_id', link_id.to_s) unless preview_mode
      element.replace_with(link_element)
    end
    doc.write(processed)
    return processed
  end

  ##############################################
  # Code to rename links within the text.
  # This assumes that the name change has already
  # taken place within the article table in the DB
  ##############################################
  def rename_article_links(old_title, new_title)
    # handle links of the format [[Old Title|Display Text]]
    self.source_text=self.source_text.gsub(/\[\[#{old_title}\|/, "[[#{new_title}|")
    # handle links of the format [[Old Title]]
    self.source_text=self.source_text.gsub(/\[\[#{old_title}\]\]/, "[[#{new_title}|#{old_title}]]")
    self.save!
  end

  def debug(msg)
    logger.debug("DEBUG: #{msg}")
  end

end
