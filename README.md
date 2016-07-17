# CULearn Grade Scraper
A script to easily grab all your grades for individual tests, labs, assignments, etc. from Carleton University's online portal, and save to JSON.

## Setup
Clone the repo: <br/>
```
$ git clone https://github.com/jktin12/GradeScraper.git
```

Install dependencies: <br/>
```
$ bundle
```

*If you are using Windows, you may need to resolve SSL issues.*

## Usage
Execute: <br/>
```
$ ruby scrape.rb
```

Choose verbose or non-verbose mode: <br/>
```
Enable verbose mode? (y/n)
```

Enter CULearn credentials: <br/>
```
Username: myusername
Password: *******
```

When the script is finished, choose whether to save to a JSON file: <br/>
```
Save to JSON file? (y/n)
y
Name of JSON file?
my_grades
Saving to my_grades.json
Finished
```

*You can enter a JSON filename with or without the .json extension.*

The JSON that is generated is in the form:
```
{
  "courses": [
    {
      "culearn_id": "",
      "name": "",
      "items": [
        {
          "name": "",
          "grade": "",
          "max": ""
        }
      ]
    }
  ]
}
```
