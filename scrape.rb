require 'nokogiri'
require 'http'
require 'highline/import'
require 'pry-byebug'

$cookies = {}

def success?(response)
  (200...300).cover? response.code
end

def perform_login_redirect(html)
  page = Nokogiri::HTML(html)
  HTTP.get(page.css('a')[0]['href'])
end

def login(username, password)
  login_response = HTTP.post(
    'https://culearn.carleton.ca/moodle/login/index.php',
    form: { username: username, password: password, Submit: 'login' }
  )
  response = perform_login_redirect(login_response.to_s)
  if success?(response)
    puts 'Login successful'
    return login_response.headers['Set-Cookie']
  else
    puts "Login failed with #{response.code}"
  end
end

def get_courses_page
  response = HTTP.cookies($cookies).get(
    'https://culearn.carleton.ca/moodle/my/'
  )
  if success?(response)
    puts 'Courses page fetched'
    return Nokogiri::HTML(response.to_s)
  else
    puts "Fetch failed with Code: #{response.code} Data: #{response}"
  end
end

def get_grade_report(course_id)
  response = HTTP.cookies($cookies).get(
    'https://culearn.carleton.ca/moodle/grade/report/user/index.php',
    params: { id: course_id }
  )
  if success?(response)
    puts 'Grade report fetched'
    return Nokogiri::HTML(response.to_s)
  else
    puts "Fetch failed with Code: #{response.code} Data: #{response}"
  end
end

####### Program Start ##########

username = ask('Username: ')
password = ask('Password: ') { |q| q.echo = false }
# num_semesters = ask('# Semesters: ')

puts 'Start scrape'
set_cookies = login(username, password)
set_cookies.each do |variable|
  x = variable.split(' ')[0].split('=')
  $cookies[x[0]] = x[1].chomp(';') if x[0].eql? 'MoodleSession'
end
courses = []
courses_page = get_courses_page
courses_page.css('.courses .course').each do |course|
  # binding.pry
  courses.push course.css('a')[0]['href'].split('?id=')[1] # get id from url params
end
courses.each do |course_id|
  grade_page = get_grade_report(course_id)
  puts ' Name    Grade    Range'
  grade_page.css('.generaltable.user-grade tbody tr').each do |grade_item|
    print grade_item.css('th.column-itemname').text + ' '
    print grade_item.css('td.column-grade').text + ' '
    puts grade_item.css('td.column-range').text
  end
end
puts 'Finish scrape'
