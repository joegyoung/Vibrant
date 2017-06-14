Vibrant
==============
A Ruby port of [Vibrant.js](https://jariz.github.io/vibrant.js/).

Extracts prominent colors from a provided image.

## Prerequisites
- Imagemagick
- Ruby >= 2.0.0

## Installation

```sh
gem install vibrant
```

## Usage

```ruby
require 'vibrant'

# Open up an image file

vibrant = Vibrant.new(File.open('someimage.jpg', 'r'))

vibrant.swatches # returns 'swatches' for the different prominent colors

```

## License

**MIT** - See `LICENSE.txt`.

