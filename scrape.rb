require 'nokogiri'
require 'http'
require 'timeout'
require 'json'
require 'highline/import'
require 'pry-byebug'

# CONSTANTS #
CULEARN_HYPHEN = '–'.freeze # this is a different hyphen than a regular one, had to copy and paste from CULearn
ITEM_MAX_WIDTH = 40 # width of output column for grade item name
LOGIN_TIMEOUT = 15 # CULearn is terribly inconsistent, and sometimes even slower than 15s for a response

# GLOBAL #
$cookies = {}

# CULearn uses a redirect with a get on login.
# Therefore, regardless of whether the credentials worked, we get the same http response.
# Need to check uri for 'testsession', which indicates a successful login.
def login_success?(response)
  response.uri.to_s.include? 'testsession'
end

# Is the http code in the 200 range
def success?(response)
  (200...300).cover? response.code # useless, CULearn always gives 200 OK
end

# Use the initial response from CULearn and navigate to the redirect destination
def perform_login_redirect(html)
  page = Nokogiri::HTML(html)
  HTTP.get(page.css('a')[0]['href'])
end

# Ask for credentials and perform the login.
def login
  login_success = false
  login_response = {}
  until login_success

    # get credentials
    username = ask('Username: ')
    password = ask('Password: ') { |q| q.echo = '*' } # hide password in terminal
    puts "Attempting to log into CULearn as user [ #{username} ]"

    # try to log in to CULearn, protect timeout
    begin
      Timeout.timeout(LOGIN_TIMEOUT) do
        login_response = HTTP.post(
          'https://culearn.carleton.ca/moodle/login/index.php',
          form: { username: username, password: password, Submit: 'login' }
        )
      end
    rescue Timeout::Error
      puts 'Could not reach the CULearn server. The server may be down.  Check your internet connection.'
      return :abort
    end

    # redirect based on response redirect destination
    response = perform_login_redirect(login_response.to_s)
    login_success = login_success?(response)
    puts login_success ? 'Login successful' : 'Login failed. Please try again.'
  end
  return login_response.headers['Set-Cookie'] if login_success
  :abort # otherwise abort
end

# Helper, makes a get to the specified uri using global cookies. GET params optional.
# The success message must be passed in. Failure message is pre-defined.
def retrieve_page(uri, success_msg, params)
  response =
    if params
      HTTP.cookies($cookies).get(uri, params: params)
    else
      HTTP.cookies($cookies).get(uri)
    end
  if success?(response)
    puts success_msg
    return Nokogiri::HTML(response.to_s)
  else
    puts "Fetch failed with Code: #{response.code} Data: #{response}"
  end
end

# Get the CULearn page with all the courses
def retrieve_courses_page
  retrieve_page('https://culearn.carleton.ca/moodle/my/',
                'Courses page retrieved',
                nil)
end

# Get the CULearn grade report page for a course with id `course_id`
def retrieve_grade_report(course_id)
  retrieve_page('https://culearn.carleton.ca/moodle/grade/report/user/index.php',
                "Grade report retrieved [#{course_id}]",
                id: course_id)
end

# OUTPUT Methods
# Naming convention - use puts if it leaves a newline afterwards

def puts_course(course)
  puts "\nCourse: " + course[:name]
  printf "%-#{ITEM_MAX_WIDTH}s %s\n", 'Name', 'Grade'
  course[:items].each do |item|
    puts_grade_item(item)
  end
end

def puts_grade_item(grade_item)
  printf "%-#{ITEM_MAX_WIDTH}s", grade_item[:name][0..(ITEM_MAX_WIDTH - 2)]
  print grade_item[:grade]
  print '/' + grade_item[:max]
  puts
end

#############################
# Main
#############################

# num_semesters = ask('# Semesters: ')

puts 'CULearn Grade Scraper'

verbose_enabled = ask 'Enable verbose mode? (y/n)'
verbose_enabled = verbose_enabled.downcase.include? 'y'

# Log in and set cookies
set_cookies = login
if set_cookies == :abort
  puts 'Aborted.'
  abort
end
set_cookies.each do |cookie|
  kv_pair = cookie.split(' ')[0].split('=')
  $cookies[kv_pair[0]] = kv_pair[1].chomp(';') if kv_pair[0].eql? 'MoodleSession'
end

# Get list of CULearn course IDs
culearn_courses = []
puts 'Retrieving course list...'
courses_page = retrieve_courses_page
courses_page.css('.courses .course').each do |course|
  culearn_courses.push course.css('a')[0]['href'].split('?id=')[1] # get id from url params
end

# Parse grade report pages. Display grades and build results hash map
puts "Parsing courses\n"

results = { courses: [] }
# Format of the hash map:
# courses: [
#   {
#     name: "",
#     culearn_id: "",
#     items: [
#       {
#         name: "",
#         grade: "",
#         max: ""
#       }
#     ]
#   }
# ]

culearn_courses.each do |course_id|
  # Get the grade report page
  grade_page = retrieve_grade_report(course_id)
  if grade_page.xpath('//text()').to_s.include? 'Grader report'
    # TA course does not have individual grades for the logged in user
    puts "TA course: skipped\n\n" if verbose_enabled
    next
  end

  # Define a new course object that will be pushed to the map afterwards
  new_course = { culearn_id: course_id, name: '', items: [] }

  # Go through each entry in the page's grade table
  grade_page.css('.generaltable.user-grade tbody tr').each_with_index do |grade_item, i|
    # Check and ignore if the table contains an empty <tr>
    next if grade_item.css('th.column-itemname').to_s.strip == ''

    # The first row contains the name of the course
    if i.zero?
      course_name = grade_item.css('th.column-itemname').text
      new_course[:name] = course_name

    # All other rows contain grade items
    else
      name = grade_item.css('th.column-itemname').text
      grade = grade_item.css('td.column-grade').text
      range = grade_item.css('td.column-range').text
      max = 'NA'
      if range.strip != ''
        # if the range text is not empty.
        # Check if it is empty after splitting with the hyphen since range is sometimes just '-'
        max = range.split(CULEARN_HYPHEN).last unless range.split(CULEARN_HYPHEN).empty?
      end
      new_course[:items].push(name: name, grade: grade, max: max)
    end
  end
  results[:courses].push new_course
  puts_course(new_course) if verbose_enabled
end

save_json = ask 'Output to json? (y/n)'
if save_json.downcase.include? 'y'
  json_filename = ask('Name of json file?').chomp '.json'
  puts "Saving to #{json_filename}.json"
  File.open("#{json_filename}.json", 'w') do |file|
    file.write(JSON.pretty_generate(results))
  end
end

puts 'Finished'
