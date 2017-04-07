require 'timeout'
require 'open3'

class GSpotMichael

  TARGET_DARK_LUMA = 0.26
  MAX_DARK_LUMA = 0.45
  MIN_LIGHT_LUMA = 0.55
  TARGET_LIGHT_LUMA = 0.74

  MIN_NORMAL_LUMA = 0.3
  TARGET_NORMAL_LUMA = 0.5
  MAX_NORMAL_LUMA = 0.7

  TARGET_MUTED_SATURATION = 0.3
  MAX_MUTED_SATURATION = 0.4

  TARGET_VIBRANT_SATURATION = 1
  MIN_VIBRANT_SATURATION = 0.35

  WEIGHT_SATURATION = 3
  WEIGHT_LUMA = 6
  WEIGHT_POPULATION = 1

  def initialize(file, colorCount=64, quality='5%')
    @HighestPopulation = 0

    # we're going to take the original file,
    # reduce the size, quantize the colors,
    # and then return an array of distinct
    # RGBs with their occurence counts(as pairs)
    file.rewind
    results = run_command "convert - -scale '#{quality}' +dither -colors #{colorCount} txt:", file.read.force_encoding("UTF-8")
    pixels  = results.split("\n").map{|x| (r = x.match(/srgb\((\d{1,3},\d{1,3},\d{1,3})\)/)) ? r[1] : nil}.compact.map{|p| p.split(",").map(&:to_i)}
    cmap    = {}
    pixels.each do |pixel|
      # If pixel is mostly opaque and not white
      if !(pixel[0] > 250 && pixel[1] > 250 && pixel[2] > 250)
        cmap[pixel] ||= 0
        cmap[pixel] += 1
      end
    end
    
    @swatches = cmap.map do |vbox|
      Swatch.new vbox[0], vbox[1]  # values, count
    end

    @maxPopulation     = find_max_population
    @HighestPopulation = @maxPopulation

    generate_variation_colors
    generate_empty_swatches
  end

  def generate_variation_colors
    @VibrantSwatch      = find_color_variation(TARGET_NORMAL_LUMA, MIN_NORMAL_LUMA, MAX_NORMAL_LUMA, TARGET_VIBRANT_SATURATION, MIN_VIBRANT_SATURATION, 1)
    @LightVibrantSwatch = find_color_variation(TARGET_LIGHT_LUMA, MIN_LIGHT_LUMA, 1, TARGET_VIBRANT_SATURATION, MIN_VIBRANT_SATURATION, 1)
    @DarkVibrantSwatch  = find_color_variation(TARGET_DARK_LUMA, 0, MAX_DARK_LUMA, TARGET_VIBRANT_SATURATION, MIN_VIBRANT_SATURATION, 1)
    @MutedSwatch        = find_color_variation(TARGET_NORMAL_LUMA, MIN_NORMAL_LUMA, MAX_NORMAL_LUMA, TARGET_MUTED_SATURATION, 0, MAX_MUTED_SATURATION)
    @LightMutedSwatch   = find_color_variation(TARGET_LIGHT_LUMA, MIN_LIGHT_LUMA, 1, TARGET_MUTED_SATURATION, 0, MAX_MUTED_SATURATION)
    @DarkMutedSwatch    = find_color_variation(TARGET_DARK_LUMA, 0, MAX_DARK_LUMA, TARGET_MUTED_SATURATION, 0, MAX_MUTED_SATURATION)
  end

  def generate_empty_swatches
    if !@VibrantSwatch
      # If we do not have a vibrant color...
      if @DarkVibrantSwatch
        # ...but we do have a dark vibrant, generate the value by modifying the luma
        hsl    = @DarkVibrantSwatch.hsl
        hsl[2] = TARGET_NORMAL_LUMA
        @VibrantSwatch = Swatch.new hslToRgb(hsl[0], hsl[1], hsl[2]), 0
      end
    end

    if !@DarkVibrantSwatch
      # If we do not have a vibrant color...
      if @VibrantSwatch
        # ...but we do have a dark vibrant, generate the value by modifying the luma
        hsl    = @VibrantSwatch.hsl
        hsl[2] = TARGET_DARK_LUMA
        @DarkVibrantSwatch = Swatch.new hslToRgb(hsl[0], hsl[1], hsl[2]), 0
      end
    end
  end

  def find_max_population
    population = @swatches.map{|swatch| [0, swatch.population].max }.max
    population
  end

  def find_color_variation (targetLuma, minLuma, maxLuma, targetSaturation, minSaturation, maxSaturation)
    max      = nil
    maxValue = 0
    
    @swatches.each do |swatch|
      sat  = swatch.hsl[1]
      luma = swatch.hsl[2]
      if !is_already_selected(swatch) && sat >= minSaturation && sat <= maxSaturation && luma >= minLuma && luma <= maxLuma
        value = create_comparison_value sat, targetSaturation, luma, targetLuma, swatch.population, @HighestPopulation
        if !max || value > maxValue
          max      = swatch
          maxValue = value
        end
      end
    end

    max
  end

  def create_comparison_value(saturation, targetSaturation, luma, targetLuma, population, maxPopulation)
    # pop = (maxPopulation != 0) ? (population / maxPopulation) : 0.0
    weighted_mean(
      invert_diff(saturation, targetSaturation), WEIGHT_SATURATION,
      invert_diff(luma, targetLuma), WEIGHT_LUMA,
      (population / maxPopulation), WEIGHT_POPULATION
    )
  end

  def invert_diff (value, targetValue)
    1 - (value - targetValue).abs
  end

  def weighted_mean(*values)
    sum = 0
    sumWeight = 0
    i = 0
    while i < values.length
      value = values[i]
      weight = values[i + 1]
      sum += value * weight
      sumWeight += weight
      i += 2
    end
    sum / sumWeight
  end

  def swatches
    {
      Vibrant: @VibrantSwatch,
      Muted: @MutedSwatch,
      DarkVibrant: @DarkVibrantSwatch,
      DarkMuted: @DarkMutedSwatch,
      LightVibrant: @LightVibrantSwatch,
      LightMuted: @LightMuted
    }
  end

  def is_already_selected(swatch)
    @VibrantSwatch == swatch || 
    @DarkVibrantSwatch == swatch ||
    @LightVibrantSwatch == swatch || 
    @MutedSwatch == swatch ||
    @DarkMutedSwatch == swatch || 
    @LightMutedSwatch == swatch
  end

  def hslToRgb(h, s, l)
    r = nil
    g = nil
    b = nil

    hue2rgb = Proc.new { |p, q, t|
      if t < 0
        t += 1
      end
      if t > 1
        t -= 1
      end
      if t < 1 / 6
        return p + (q - p) * 6 * t
      end
      if t < 1 / 2
        return q
      end
      if t < 2 / 3
        return p + (q - p) * (2 / 3 - t) * 6
      end
      p
    }

    if s == 0
      r = g = b = l
      # achromatic
    else
      q = (l < 0.5) ? (l * (1 + s)) : (l + s - (l * s))
      p = 2 * l - q
      r = hue2rgb.call(p, q, h + 1 / 3)
      g = hue2rgb.call(p, q, h)
      b = hue2rgb.call(p, q, h - (1 / 3))
    end
    [
      r * 255,
      g * 255,
      b * 255
    ]
  end

  def run_command command, input
    stdin, stdout, stderr, wait_thr = Open3.popen3(command)
    pid = wait_thr.pid

    Timeout.timeout(10) do # cancel in 10 seconds
      stdin.write input
      stdin.close

      output_buffer = []
      error_buffer  = []

      while (output_chunk = stdout.gets) || (error_chunk = stderr.gets)
        output_buffer << output_chunk
        error_buffer  << error_chunk
      end

      output_buffer.compact!
      error_buffer.compact!

      output = output_buffer.any? ? output_buffer.join('') : nil
      error  = error_buffer.any?  ? error_buffer.join('')  : nil

      unless error
        raise StandardError.new("No output received.") if !output
        return output
      else
        raise StandardError.new(error)
      end
    end
  rescue Timeout::Error, StandardError, Errno::EPIPE => e
    e
  ensure
    begin
      Process.kill("KILL", pid) if pid
    rescue Errno::ESRCH
      # Process is already dead so do nothing.
    end
    stdin  = nil
    stdout = nil
    stderr = nil
    wait_thr.value if wait_thr # Process::Status object returned.
  end

  class Swatch

    attr_accessor :rgb, :population

    def initialize(rgb, population=1)
      @rgb = rgb
      @population = population
      @yiq = 0
    end

    def hsl
      @hsl ||= rgb_to_hsl @rgb[0], @rgb[1], @rgb[2]
    end

    def hex
      "#" + ((1 << 24) + (@rgb[0] << 16) + (@rgb[1] << 8) + @rgb[2]).to_s(16).slice(1, 7)
    end

    def get_title_text_color
      ensure_text_colors
      (@yiq < 200) ? "#fff" : "#000"
    end

    def get_body_text_color
      ensure_text_colors
      (@yiq < 150) ? "#fff" : "#000"
    end

    private

    def ensure_text_colors
      if @yiq != 0 
        @yiq = (@rgb[0] * 299 + @rgb[1] * 587 + @rgb[2] * 114) / 1000
      end
    end

    def rgb_to_hsl(r, g, b)
      r = r.to_f / 255.0
      g = g.to_f / 255.0
      b = b.to_f / 255.0
      max = [r, g, b].max
      min = [r, g, b].min
      h = 0.0
      s = 0.0
      l = (max + min) / 2
      unless max == min # if not achromatic
        d = max - min
        s = (l > 0.5) ? (d / (2 - max - min)) : (d / (max + min))
        case max
        when r
          h = (g - b) / d + ((g < b) ? 6 : 0)
        when g
          h = (b - r) / d + 2
        when b
          h = (r - g) / d + 4
        end
        h = h / 6
      end
      [h, s, l]
    end

  end

end

