require 'digest'
require 'json'
require 'fileutils'
require 'yaml'
require 'base64'

# Monkey patching hash
class Hash
  def fetch2(key, default)
    fetch(key, default) || default
  end
end

# Generate Notebooks from Markdown
module Gtn
  ##
  # Notebook generation module, this converts markdown into Jupyter and RMarkdown/Quarto notebooks
  module Notebooks

    # Colors for the various boxes, based on our 2024 CSS
    COLORS = {
      'overview' => '#8A9AD0',
      'agenda' => '#86D486',
      'keypoints' => '#FFA1A1',
      'tip' => '#FFE19E',
      'warning' => '#de8875',
      'comment' => '#ffecc1',
      'hands_on' => '#dfe5f9',
      'question' => '#8A9AD0',
      'solution' => '#B8C3EA',
      'details' => '#ddd',
      'feedback' => '#86D486',
      'code-in' => '#86D486',
      'code-out' => '#fb99d0',
    }.freeze

    # +COLORS+ but hide the agenda box.
    COLORS_EXTRA = {
      'agenda' => 'display: none',
    }.freeze

    # Emoji icons for the various boxes
    ICONS = {
      'tip' => '💡',
      'code-in' => '⌨️',
      'code-out' => '🖥',
      'question' => '❓',
      'solution' => '👁',
      'warning' => '⚠️',
      'comment' => '💬',
      'feedback' => '⁉️',
      'details' => '💬',
      'hands_on' => '✏️',
    }.freeze

    # Font-awesome equivalents of the icons we use for our boxes
    ICONS_FA = {
      'far fa-keyboard' => 'code-in',
      'fas fa-laptop-code' => 'code-out',
      'far fa-comment-dots' => 'comment',
      'fas fa-info-circle' => 'details',
      'far fa-comments' => 'feedback',
      'fas fa-pencil-alt' => 'hands_on',
      'far fa-question-circle' => 'question',
      'far fa-eye' => 'solution',
      'far fa-lightbulb' => 'tip',
      'fas fa-exclamation-triangle' => 'warning',
    }.freeze

    # Generate the CSS to be included, by mapping our colors to appropriate classes.
    def self.generate_css
      COLORS.map do |key, val|
        ".#{key} { padding: 0 1em; margin: 1em 0.2em; border: 2px solid #{val} }"
      end.join("\n")
    end

    ##
    # Convert a markdown file into a Jupyter notebook JSON structure.
    #
    # Params:
    # +content+:: The markdown content to convert
    # +accepted_languages+:: The languages to accept as code blocks. Code blocks that do not match will not be accepted.
    #
    # Returns:
    # +Hash+:: A JSON structure representing the Jupyter notebook.
    def self.convert_notebook_markdown(content, accepted_languages)
      out = []
      inside_block = false
      cur_lang = nil
      val = []
      data = content.split("\n")
      data.each.with_index do |line, i|
        m = line.match(/^```(#{accepted_languages.join('|')})\s*$/)
        if m
          if inside_block
            puts data[i - 2..i + 2]
            raise "[GTN/Notebook] L#{i} Error! we're already in a block:"
          end
          # End the previous block
          out.push([val, inside_block, cur_lang])
          val = []

          inside_block = true
          cur_lang = m[1]
        elsif inside_block && line == '```'
          # End of code block
          out.push([val, inside_block, cur_lang])
          val = []
          inside_block = false
        else
          val.push(line)
        end
      end
      # final flush
      out.push([val, inside_block, cur_lang]) if !val.nil?

      notebook = {
        'metadata' => {},
        'nbformat' => 4,
        'nbformat_minor' => 5,
      }

      notebook['cells'] = out.map.with_index do |data2, index|
        res = {
          'id' => "cell-#{index}",
          'source' => data2[0].map { |x| "#{x.rstrip}\n" }
        }
        # Strip the trailing newline in the last cell.
        res['source'][-1] = res['source'][-1].rstrip if res['source'].length.positive?

        # Remove any remaining language tagged code blocks, e.g. in
        # tip/solution/etc boxes. These do not render well.
        res['source'] = res['source'].map { |x| x.gsub(/```(#{accepted_languages.join('|')})/, '```') }

        if data2[1]
          res.update({
                       'cell_type' => 'code',
                       'execution_count' => nil,
                       'outputs' => [],
                       'metadata' => {
                         'attributes' => {
                           'classes' => [
                             data[2]
                           ],
                           'id' => '',
                         }
                       }
                     })
        else
          res['cell_type'] = 'markdown'
        end
        res
      end
      notebook
    end

    ##
    # Group a document by the first character seen, which extracts blockquotes mostly.
    def self.group_doc_by_first_char(data)
      out = []
      first_char = nil
      val = []
      data = data.split("\n")

      # Here we collapse running groups of `>` into single blocks.
      data.each do |line|
        if first_char.nil?
          first_char = line[0]
          val = [line]
        elsif line[0] == first_char
          val.push(line)
        elsif line[0..1] == '{:' && first_char == '>'
          val.push(line)
        else
          # flush
          out.push(val)
          first_char = if line.size.positive?
                         line[0]
                       else
                         ''
                       end
          val = [line]
        end
      end
      # final flush
      out.push(val)

      out.reject! do |v|
        (v[0][0] == '>' && v[-1][0..1] == '{:' && v[-1].match(/.agenda/))
      end
      out.map! do |v|
        if v[0][0] == '>' && v[-1][0..1] == '{:'
          cls = v[-1][2..-2].strip
          res = [":::{#{cls}}"]
          res += v[0..-2].map { |c| c.sub(/^>\s*/, '') }
          res += [':::']
          res
        else
          v
        end
      end

      out.flatten(1).join("\n")
    end

    ##
    # Construct a byline from the metadata
    #
    # Params:
    # +site+:: The Jekyll site object
    # +metadata+:: The metadata to construct the byline from, including a contributions or contributors key
    #
    # Returns:
    # +String+:: The byline with markdown hyperlinks to the contributors
    def self.construct_byline(site, metadata)
      folks = Gtn::Contributors.get_authors(metadata)
      folks.map do |c|
        name = Gtn::Contributors.fetch_name(site, c)
        "[#{name}](https://training.galaxyproject.org/hall-of-fame/#{c}/)"
      end.join(', ')
    end

    ##
    # Given a notebook, add the metadata cell to the top of the notebook with the agenda, license, LOs, etc.
    #
    # Params:
    # +site+:: The Jekyll site object
    # +notebook+:: The notebook to add the metadata cell to
    # +metadata+:: The page.data to construct use for metadata.
    #
    # Returns:
    # +Hash+:: The updated notebook with the metadata cell added to the top.
    def self.add_metadata_cell(site, notebook, metadata)
      by_line = construct_byline(site, metadata)

      meta_header = [
        "<div style=\"border: 2px solid #8A9AD0; margin: 1em 0.2em; padding: 0.5em;\">\n\n",
        "# #{metadata['title']}\n",
        "\n",
        "by #{by_line}\n",
        "\n",
        "#{metadata.fetch('license', 'CC-BY')} licensed content from the [Galaxy Training Network]" \
        "(https://training.galaxyproject.org/)\n",
        "\n",
        "**Objectives**\n",
        "\n"
      ] + metadata.fetch2('questions', []).map { |q| "- #{q}\n" } + [
        "\n",
        "**Objectives**\n",
        "\n"
      ] + metadata.fetch2('objectives', []).map { |q| "- #{q}\n" } + [
        "\n",
        "**Time Estimation: #{metadata['time_estimation']}**\n",
        "\n",
        "</div>\n"
      ]
      metadata_cell = {
        'id' => 'metadata',
        'cell_type' => 'markdown',
        'source' => meta_header
      }
      notebook['cells'].unshift(metadata_cell)
      notebook
    end

    ##
    # Fix an R based Jupyter notebook by setting the kernel to R and stripping out the %%R magic commands.
    def self.fixRNotebook(notebook)
      # Set the bash kernel
      notebook['etadata'] = {
        'kernelspec' => {
          'display_name' => 'R',
          'language' => 'R',
          'name' => 'r'
        },
        'language_info' => {
          'codemirror_mode' => 'r',
          'file_extension' => '.r',
          'mimetype' => 'text/x-r-source',
          'name' => 'R',
          'pygments_lexer' => 'r',
          'version' => '4.1.0'
        }
      }
      # Strip out %%R since we'll use the bash kernel
      notebook['cells'].map do |cell|
        if cell.fetch('cell_type') == 'code' && (cell['source'][0] == "%%R\n")
          cell['source'] = cell['source'].slice(1..-1)
        end
        cell
      end
      notebook
    end

    ##
    # Similar to +fixRNotebook+ but for bash.
    def self.fixBashNotebook(notebook)
      # Set the bash kernel
      notebook['metadata'] = {
        'kernelspec' => {
          'display_name' => 'Bash',
          'language' => 'bash',
          'name' => 'bash'
        },
        'language_info' => {
          'codemirror_mode' => 'shell',
          'file_extension' => '.sh',
          'mimetype' => 'text/x-sh',
          'name' => 'bash'
        }
      }
      # Strip out %%bash since we'll use the bash kernel
      notebook['cells'].map do |cell|
        if cell.fetch('cell_type') == 'code' && (cell['source'][0] == "%%bash\n")
          cell['source'] = cell['source'].slice(1..-1)
        end
        cell
      end
      notebook
    end

    ##
    # Similar to +fixRNotebook+ but for Python, bash cells are accepted but must be prefixed with !
    def self.fixPythonNotebook(notebook)
      # TODO
      # prefix bash cells with `!`
      notebook['cells'].map do |cell|
        if cell.fetch('metadata', {}).fetch('attributes', {}).fetch('classes', [])[0] == 'bash'
          cell['source'] = cell['source'].map { |line| "!#{line}" }
        end
        cell
      end
      notebook
    end

    ##
    # Ibid, +fixRNotebook+ but for SQL.
    def self.fixSqlNotebook(notebook)
      # Add in a %%sql at the top of each cell
      notebook['cells'].map do |cell|
        if cell.fetch('cell_type') == 'code' && cell['source'].join.index('load_ext').nil?
          cell['source'] = ["%%sql\n"] + cell['source']
        end
        cell
      end
      notebook
    end

    ##
    # Call Jekyll's markdown plugin or failover to Kramdown
    #
    # I have no idea why that failure mode is supported, that's kinda wild.
    #
    # Params:
    # +site+:: The Jekyll site object
    # +text+:: The text to convert to html
    #
    # Returns:
    # +String+:: The HTML representation
    def self.markdownify(site, text)
      site.find_converter_instance(
        Jekyll::Converters::Markdown
      ).convert(text.to_s)
    rescue StandardError
      require 'kramdown'
      Kramdown::Document.new(text).to_html
    end

    ##
    # Return true if it's a notebook and the language is correct
    #
    # TODO: convert to `notebook?` which is more ruby-esque.
    #
    # +data+:: The page data to check
    # +language+:: The language to check for
    #
    # Returns:
    # +Boolean+:: True if it's a notebook (i.e hands on tutorial, has a notebook key, and the language is correct)
    def self.notebook_filter(data, language = nil)
      data['layout'] == 'tutorial_hands_on' \
        and data.key?('notebook') \
        and (language.nil? or data['notebook']['language'].downcase == language)
    end

    ##
    # Massage a page into RMarkdown preferred formatting.
    #
    # Params:
    # +site+:: The Jekyll site object
    # +page_data+:: The page metadata (page.data)
    # +page_content+:: The page content (page.content)
    # +page_url+:: The page URL
    # +page_last_modified+:: The last modified time of the page
    # +fn+:: The source filename of the page
    #
    # Returns:
    # +String+:: The RMarkdown formatted content
    #
    def self.render_rmarkdown(site, page_data, page_content, page_url, page_last_modified, fn)
      by_line = construct_byline(site, page_data)

      # Replace top level `>` blocks with fenced `:::`
      content = group_doc_by_first_char(page_content)

      # Re-run a second time to catch singly-nested Q&A?
      content = group_doc_by_first_char(content)

      # Replace zenodo links, the only replacement we do
      if !page_data['zenodo_link'].nil?
        Jekyll.logger.debug "Replacing zenodo links in #{page_url}, #{page_data['zenodo_link']}"
        content.gsub!(/{{\s*page.zenodo_link\s*}}/, page_data['zenodo_link'])
      end

      ICONS.each do |key, val|
        content.gsub!(/{% icon #{key} %}/, val)
      end
      ICONS_FA.each do |key, val|
        content.gsub!(%r{<i class="#{key}" aria-hidden="true"></i>}, ICONS[val])
      end

      content += %(\n\n# References\n\n<div id="refs"></div>\n)

      # https://raw.githubusercontent.com/rstudio/cheatsheets/master/rmarkdown-2.0.pdf
      # https://bookdown.org/yihui/rmarkdown/

      fnparts = fn.split('/')
      rmddata = {
        'title' => page_data['title'],
        'author' => "#{by_line}, #{page_data.fetch('license',
                                                   'CC-BY')} licensed content from the [Galaxy Training Network](https://training.galaxyproject.org/)",
        'bibliography' => "#{fnparts[2]}-#{fnparts[4]}.bib",
        'output' => {
          'html_notebook' => {
            'toc' => true,
            'toc_depth' => 2,
            'css' => 'gtn.css',
            'toc_float' => {
              'collapsed' => false,
              'smooth_scroll' => false,
            },
            # 'theme' => {'bootswatch' => 'journal'}
          },
          'word_document' => {
            'toc' => true,
            'toc_depth' => 2,
            'latex_engine' => 'xelatex',
          },
          'pdf_document' => {
            'toc' => true,
            'toc_depth' => 2,
            'latex_engine' => 'xelatex',
          },
        },
        'date' => page_last_modified.to_s,
        'link-citations' => true,
        'anchor_sections' => true,
        'code_download' => true,
      }
      rmddata['output']['html_document'] = JSON.parse(JSON.generate(rmddata['output']['html_notebook']))

      final_content = [
        "# Introduction\n",
        content.gsub(/```[Rr]/, '```{r}'),
        "# Key Points\n"
      ] + page_data.fetch2('key_points', []).map { |k| "- #{k}" } + [
        "\n# Congratulations on successfully completing this tutorial!\n",
        'Please [fill out the feedback on the GTN website](https://training.galaxyproject.org/' \
        "training-material#{page_url}#feedback) and check there for further resources!\n"
      ]

      "#{rmddata.to_yaml(line_width: rmddata['author'].size + 10)}---\n#{final_content.join("\n")}"
    end


    def self.render_jupyter_notebook(data, content, url, _last_modified, notebook_language, site, dir)
      # Here we read use internal methods to convert the tutorial to a Hash
      # representing the notebook
      accepted_languages = [notebook_language]
      accepted_languages << 'bash' if notebook_language == 'python'

      if !data['zenodo_link'].nil?
        Jekyll.logger.debug "Replacing zenodo links in #{url}, #{data['zenodo_link']}"
        content.gsub!(/{{\s*page.zenodo_link\s*}}/, data['zenodo_link'])
      end
      notebook = convert_notebook_markdown(content, accepted_languages)
      # This extracts the metadata yaml header and does manual formatting of
      # the header data to make for a nicer notebook.
      notebook = add_metadata_cell(site, notebook, data)

      # Apply language specific conventions
      case notebook_language
      when 'bash'
        notebook = fixBashNotebook(notebook)
      when 'sql'
        notebook = fixSqlNotebook(notebook)
      when 'r'
        notebook = fixRNotebook(notebook)
      when 'python'
        notebook = fixPythonNotebook(notebook)
      end

      # Here we loop over the markdown cells and render them to HTML. This
      # allows us to get rid of classes like {: .tip} that would be left in
      # the output by Jupyter's markdown renderer, and additionally do any
      # custom CSS which only seems to work when inline on a cell, i.e. we
      # can't setup a style block, so we really need to render the markdown
      # to html.
      notebook = renderMarkdownCells(site, notebook, data, url, dir)

      # Here we add a close to the notebook
      notebook['cells'] = notebook['cells'] + [{
        'cell_type' => 'markdown',
        'id' => 'final-ending-cell',
        'metadata' => { 'editable' => false, 'collapsed' => false },
        'source' => [
          "# Key Points\n\n"
        ] + data.fetch2('key_points', []).map { |k| "- #{k}\n" } + [
          "\n# Congratulations on successfully completing this tutorial!\n\n",
          'Please [fill out the feedback on the GTN website](https://training.galaxyproject.org/training-material' \
          "#{url}#feedback) and check there for further resources!\n"
        ]
      }]
      notebook
    end

    def self.renderMarkdownCells(site, notebook, metadata, _page_url, dir)
      seen_abbreviations = {}
      notebook['cells'].map do |cell|
        if cell.fetch('cell_type') == 'markdown'

          # The source is initially a list of strings, we'll merge it together
          # to make it easier to work with.
          source = cell['source'].join.strip

          # Here we replace individual `s with codeblocks, they screw up
          # rendering otherwise by going through rouge
          source = source.gsub(/ `([^`]*)`([^`])/, ' <code>\1</code>\2')
                         .gsub(/([^`])`([^`]*)` /, '\1<code>\2</code> ')

          # Strip out includes, snippets
          source.gsub!(/{% include .* %}/, '')
          source.gsub!(/{% snippet .* %}/, '')

          # Replace all the broken icons that can't render, because we don't
          # have access to the full render pipeline.
          cell['source'] = markdownify(site, source)

          ICONS.each do |key, val|
            # Replace the new box titles with h3s.
            cell['source'].gsub!(%r{<div class="box-title #{key}-title".*?</span>(.*?)</div>},
                                 "<div style=\"font-weight:900;font-size: 125%\">#{val} \\1</div>")

            # Remove the fa-icon spans
            cell['source'].gsub!(%r{<span role="button" class="fold-unfold fa fa-minus-square"></span>}, '')

            # just removing the buttons from solutions since they'll be changed
            # into summary/details in the parent notebook-jupyter.
            cell['source'].gsub!(%r{<button class="gtn-boxify-button solution".*?</button>}, '')
          end

          if metadata.key?('abbreviations')
            metadata['abbreviations'].each do |abbr, defn|
              cell['source'].gsub(/\{#{abbr}\}/) do
                if seen_abbreviations.key?(abbr)
                  firstdef = false
                else
                  firstdef = true
                  seen_abbreviations[abbr] = true
                end

                if firstdef
                  "#{defn} (#{abbr})"
                else
                  "<abbr title=\"#{defn}\">#{abbr}</abbr>"
                end
              end
            end
          end

          # Here we give a GTN-ish styling that doesn't try to be too faithful,
          # so we aren't spending time keeping up with changes to GTN css,
          # we're making it 'our own' a bit.

          COLORS.each do |key, val|
            val = "#{val};#{COLORS_EXTRA[key]}" if COLORS_EXTRA.key? key

            cell['source'].gsub!(/<blockquote class="#{key}">/,
                                 "<blockquote class=\"#{key}\" style=\"border: 2px solid #{val}; margin: 1em 0.2em\">")
          end

          # Images are referenced in the through relative URLs which is
          # fab, but in a notebook this doesn't make sense as it will live
          # outside of the GTN. We need real URLs.
          #
          # So either we'll embed the images directly via base64 encoding (cool,
          # love it) or we'll link to the production images and folks can live
          # without their images for a bit until it's merged.

          if cell['source'].match(/<img src="\.\./)
            cell['source'].gsub!(/<img src="(\.\.[^"]*)/) do |img|
              path = img[10..]
              image_path = File.join(dir, path)

              if img[-3..].downcase == 'png'
                data = Base64.encode64(File.binread(image_path))
                %(<img src="data:image/png;base64,#{data}")
              elsif (img[-3..].downcase == 'jpg') || (img[-4..].downcase == 'jpeg')
                data = Base64.encode64(File.binread(image_path))
                %(<img src="data:image/jpeg;base64,#{data}")
              elsif img[-3..].downcase == 'svg'
                data = Base64.encode64(File.binread(image_path))
                %(<img src="data:image/svg+xml;base64,#{data}")
              else
                # Falling back to non-embedded images
                "<img src=\"https://training.galaxyproject.org/training-material/#{page_url.split('/')[0..-2].join('/')}/.."
              end
            end
          end

          # Strip out the highlighting as it is bad on some platforms.
          cell['source'].gsub!(/<pre class="highlight">/, '<pre style="color: inherit; background: transparent">')
          cell['source'].gsub!(/<div class="highlight">/, '<div>')
          cell['source'].gsub!(/<code>/, '<code style="color: inherit">')

          # There is some weirdness in the processing of $s in Jupyter. After a
          # certain number of them, it will give up, and just render everything
          # like with a '<pre>'. We remove this to prevent that result.
          cell['source'].gsub!(/^\s*</, '<')
          # Additionally leading spaces are sometimes interpreted as <pre>s and
          # end up causing paragraphs to be rendered as code. So we wipe out
          # all leading space.
          # 'editable' is actually CoCalc specific but oh well.
          cell['metadata'] = { 'editable' => false, 'collapsed' => false }
          cell['source'].gsub!(/\$/, '&#36;')
        end
        cell
      end
      notebook
    end
  end
end
