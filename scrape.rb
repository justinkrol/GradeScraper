require "nokogiri"
require "http"

$cookies = Hash.new()

def is_success(response)
    return (200...300).include? response.code
end

def perform_login_redirect(html)
    page = Nokogiri::HTML(html)
    return HTTP.get(page.css('a')[0]['href'])
end

def login(username, password)
    loginResponse = HTTP.post('https://culearn.carleton.ca/moodle/login/index.php', form: { username: username, password: password, Submit: "login" })
    response = perform_login_redirect(loginResponse.to_s)
    if is_success(response)
        puts 'Login successful'
        return loginResponse.headers['Set-Cookie']
    else
        puts "Login failed with #{response.code}"
    end
end

def get_grade_report(courseId)
    response = HTTP.cookies($cookies).get('https://culearn.carleton.ca/moodle/grade/report/user/index.php', params: { id: courseId })
    if is_success(response)
        puts 'Grade report fetched'
        return Nokogiri::HTML(response.to_s)
    else
        puts "Fetch failed with Code: #{response.code} Data: #{response}"
    end
end

####### Program Start ##########

username = '' # get from user
password = '' # get from user
courseId = 0 # get from user

puts 'Start scrape'
set_cookies = login(username, password)
set_cookies.each do |variable|
    x = variable.split(' ')[0].split('=')
    if x[0].eql? 'MoodleSession'
        $cookies[x[0]] = x[1].chomp(';')
    end
end
grade_page = get_grade_report(courseId)
grade_page.css('.generaltable.user-grade tbody tr td.column-grade').each do |grade_item|
   puts grade_item.text
end
puts 'Finish scrape'
