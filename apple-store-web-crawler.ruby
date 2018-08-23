#!/usr/bin/env ruby



require 'rubygems'
require 'hpricot'
require 'httparty'
require 'sqlite3' 


class String
    def string_between_markers marker1, marker2
        self[/#{Regexp.escape(marker1)}(.*?)#{Regexp.escape(marker2)}/m, 1]
    end
end

# MODIFY YOUR NATIVE LANGUAGE
NATIVE_LANGUAGE = 'en'

# MODIFY THIS HASH WITH YOUR APP SET (grab the itunes store urls & pull the id params)
software = {
  # http://phobos.apple.com/WebObjects/MZStore.woa/wa/viewSoftware?id=289923007&mt=8
  'ApppleID ' => ARGV[1],
}

stores = [
#  { :name => 'United States',        :id => 143441, :language => 'en'    },
  { :name => 'Australia',            :id => 143460, :language => 'en'    },
#  { :name => 'United Kingdom',       :id => 143444, :language => 'en'    },

]

DEBUG = false

TRANSLATE_URL = "http://ajax.googleapis.com/ajax/services/language/translate?"

def translate(opts)
  from = opts[:from] == 'auto' ? '' : opts[:from]  # replace 'auto' with blank per Translate API
  to   = opts[:to]

  result = HTTParty.get(TRANSLATE_URL, :query => { :v => '1.0', :langpair => "#{from}|#{to}", :q => opts[:text] })

  raise result['responseDetails'] if result['responseStatus'] != 200
  return result['responseData']['translatedText']
end

# return a rating/subject/author/body hash
def fetch_reviews(software_id, store, pageNo)
  reviews = []
  
  # TODO: parameterize type=Purple+Software
  cmd = sprintf(%{curl -s -A "iTunes/9.2 (Macintosh; U; Mac OS X 10.6" -H "X-Apple-Store-Front: %s" } <<
                %{'https://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?id=%s&} <<
                %{pageNumber=%s&sortOrdering=1&type=Purple+Software' | xmllint --format --recover - 2>/dev/null},
                store[:id],
                software_id,
                pageNo)

  rawxml = `#{cmd}`
  

  if defined?(DEBUG) && DEBUG == true
    open("appreview.#{software_id}.#{store[:id]}.xml", 'w') { |f| f.write(rawxml) }
  end
  
  doc = Hpricot.XML(rawxml)

  doc.search("Document > View > ScrollView > VBoxView > View > MatrixView > VBoxView:nth(0) > VBoxView > VBoxView").each do |e|
    review = {}
    
    strings = (e/:SetFontStyle)
    meta    = strings[2].inner_text.split(/\n/).map { |x| x.strip }
    review[:authorid] = `echo \"#{strings[2]}\"|delimExtract "userProfileId=" "><b>";`.strip
 
   # Note: Translate is sensitive to spaces around punctuation, so we make sure br's connote space.
    review[:rating]  = e.inner_html.match(/alt="(\d+) star(s?)"/)[1].to_i
    review[:author]  = meta[3].gsub("\'"," ").strip
    review[:version] = meta[7][/Version (.*)/, 1].strip unless meta[7].nil?
    review[:date]    = meta[10].strip
    review[:subject] = strings[0].inner_text.strip.gsub("\'"," ").strip
    review[:body]    = strings[3].inner_html.gsub("<br />", " ").gsub("\"","").gsub("\n"," ").gsub("\'"," ").strip
    #puts "#{review[:authorid]}"
    #exit
 
   if ! store[:language].empty? && store[:language] != NATIVE_LANGUAGE
      begin
        review[:subject] = translate( :from => store[:language], :to => NATIVE_LANGUAGE, :text => review[:subject] )
        review[:body]    = translate( :from => store[:language], :to => NATIVE_LANGUAGE, :text => review[:body] )
      rescue => e
        if DEBUG
          puts "** oops, cannot translate #{store[:name]}/#{store[:language]} => #{NATIVE_LANGUAGE}: #{e.message}"
        end
      end
    end
    
    reviews << review
  end

  reviews
end

begin
reviewCnt=0

db = SQLite3::Database.open "apple.db"
db.execute "CREATE TABLE IF NOT EXISTS Reviews(
    Hash TEXT PRIMARY KEY,
    AppleID INTEGER,
    AuthorID TEXT,
    Author TEXT,
    Rating TEXT,
    Version TEXT,
    Date TEXT,
    Subject TEXT,
    Body TEXT, 
    StoreName TEXT);"
stm = db.prepare "SELECT AppleID from Details"
rs = stm.execute
row = rs.next
while (row = rs.next) do
software.keys.sort.each do |software_key|
    stores.sort_by { |a| a[:name] }.each do |store|
        for page in 0..200
            row = row.join "\s"
            reviews = fetch_reviews(row, store, page)
            if reviews.any?
                reviews.each_with_index do |review, index|
                    cmd  = "echo \"#{row}#
                    {review[:authorid]}#{review[:subject]}#{review[:date]}\" | md5sum | awk {'print $1'}"
                    hash = `#{cmd}`.strip    
                    data =  sprintf(%{(\'%s\',\'%s\',\'%s\',\'%s\',\'%s\',\'%s\',\'%s\',\'%s\',\'%s\',\'%s\')},
                    hash,
                    row,
       
                    review[:authorid],
                    review[:author],
                    review[:rating],
                    review[:version],
                    review[:date],
                    review[:subject],
                    review[:body],
                    store[:name])
                    #puts "#{data}"
                    begin
                    db.execute "INSERT INTO Reviews VALUES #{data}"
                    rescue SQLite3::Exception => e 
                        puts e
                        break
                    end

                   end
            else
                break
            end
            row = rs.next
            reviewCnt = reviewCnt + 1
            print "#{reviewCnt} Completed    \r"
        end
    end
 end
end

rescue SQLite3::Exception => e
        puts "Exception Occured"
        puts e
        continue
ensure
   stm.close if stm
    db.close if db 
end


