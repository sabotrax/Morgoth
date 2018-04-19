class Ship

  def initialize(arg = {})
    unless arg.is_a? Hash
      raise ArgumentError, 'Argument is not a Hash'
    end

    @length = {
      value:  arg[:length] || 0,
      name:   'Länge',
      short_name: 'Länge',
      type: '^[1-9]\d{1,3}$',
      err_msg:  'Länge in Meter von 1 bis 999 angeben.',
      source: :local
    }

    #@beam
    #@height
    #@size
    #@mass

    #@min_crew
    #@max_crew
    #@cargo
    #@scm_speed
    #@ab_speed

    #@weapons
    #@turrets
    #@missiles
  end

  def length
    @length[:length]
  end

  def length=(l)
    unless l.to_s =~ /#{@length[:type]}/
      raise ArgumentError, @length[:err_msg]
    end

    @length[:value] = l
  end

end
