# Forecaster

Elixir application to retrieve a weather forecast and publish it to a MQTT broker.
Useful for smart home automations or anything else that requires a weather forecast.

Needs a running webdriver (e.g. locally 'phantomjs --wd')

This is not a super fast approach (give a forecast 5-6s) and you should not query data in short intervals (be nice!).
Data on their side isn't going to change too frequently anyway.

To get the correct string for the place you can search for your city, click on it and then copy the ID out of the URL.
You can go with just the number (and get a redirect) or with the hole string like "berlin_germany_2950159"

## Configuration

Connection to MQTT broker can be configured with the following env variables:
- MQTT_HOST
- MQTT_PORT
- MQTT_USER
- MQTT_PW

The Selenium host can be configured with SELENIUM_HOST (if it's not running on localhost).

Forecasts are published by default to the "home/get/forecast" MQTT topic which can be changed by setting the MQTT_NAMESPACE env variable.

## Running with docker

`docker image build -t elixir/forecaster .`

`docker run -d -e MQTT_HOST=$MQTT_HOST -e MQTT_USER=$MQTT_USER -e MQTT_PW=$MQTT_PW -e SELENIUM_HOST="172.17.0.2" -e FORECAST_PLACE="berlin_germany_2950159" elixir/forecaster start`

## Development

XPath strings can be easily retrieved through Chromes Developer Tools. To get a XPath to an element, just right-click it in the HTML view and select copy -> copy XPath.
To validate a giving XPath string you can use it like that in the console: `$x("//input[@type='submit']")`
