# Forecaster

Elixir application to retrieve a weather forecast and publish it to a MQTT broker.
Useful for smart home automations or anything else that requires a weather forecast.

To get the correct string for the place you can search for your city, click on it and then copy the ID out of the URL.
You can go with just the number (and get a redirect) or with the hole string like "berlin_germany_2950159"

## Backends

### Req + Floki

This backend fetches the html via req and then parses the result with the help of floki.
As all data is already included in the first response this is an easy and robust option to get the needed information.

### Selenium

> [!NOTE]  
> Not supported / recommended anymore

Needs a running webdriver (e.g. locally 'phantomjs --wd')

This is not a super fast approach (give a forecast 5-6s) and you should not query data in short intervals (be nice!).
Data on their side isn't going to change too frequently anyway.

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

## Usage
```elixir
iex> Forecaster.Weather.forecast("a_place_1234567")
[
    {1, %{temp_max: "27", temp_min: "16", precip_max: "0", sun: "12", uv: "7"},
        hour: %{
            1 => %{temperature: "4", condition: "Mostly cloudy"},
            2 => %{temperature: "4", condition: "Mostly cloudy"},
            3 => %{temperature: "4", condition: "Mostly cloudy"},
            4 => %{temperature: "4", condition: "Overcast with light rain"},
            5 => %{temperature: "3", condition: "Partly cloudy"},
            6 => %{temperature: "3", condition: "Partly cloudy"},
            7 => %{temperature: "4", condition: "Clear with few low clouds"},
            8 => %{temperature: "5", condition: "Clear with few low clouds"},
            9 => %{temperature: "6", condition: "Clear with few low clouds"},
            10 => %{temperature: "8", condition: "Clear with few low clouds"},
            11 => %{temperature: "9", condition: "Clear with few low clouds"},
            12 => %{temperature: "9", condition: "Partly cloudy"},
            13 => %{temperature: "9", condition: "Partly cloudy"},
            14 => %{temperature: "9", condition: "Mixed with showers"},
            15 => %{temperature: "8", condition: "Partly cloudy"},
            16 => %{temperature: "8", condition: "Partly cloudy"},
            17 => %{temperature: "7", condition: "Partly cloudy"},
            18 => %{temperature: "6", condition: "Partly cloudy"},
            19 => %{temperature: "6", condition: "Partly cloudy"},
            20 => %{temperature: "5", condition: "Partly cloudy"},
            21 => %{temperature: "5", condition: "Clear with few low clouds"},
            22 => %{temperature: "4", condition: "Clear with few low clouds"},
            23 => %{temperature: "4", condition: "Clear with few low clouds"},
            24 => %{temperature: "3", condition: "Partly cloudy"}
        }
    },
    {2, %{temp_max: "28", temp_min: "11", precip_max: "0", sun: "13", uv: "6"}},
    ...
]
```

## Development

XPath strings can be easily retrieved through Chromes Developer Tools. To get a XPath to an element, just right-click it in the HTML view and select copy -> copy XPath.
To validate a giving XPath string you can use it like that in the console: `$x("//input[@type='submit']")`
