G Spot Michael
==============
A Ruby port of [Vibrant.js](https://jariz.github.io/vibrant.js/).

Extracts prominent colors from a provided image.

## Prerequisites
- Imagemagick
- Ruby >= 2.0.0

## Installation

```sh
gem install g-spot-michael
```

## Usage

```ruby
require 'g-spot-michael'

# Open up an image file

g_spot = GSpotMichael.new(File.open('someimage.jpg', 'r'))

g_spot.swatches # returns 'swatches' for the different prominent colors

```

## License

**MIT** - See `LICENSE.txt`.

