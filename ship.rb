class Ship

  def initialize(arg = {})
    unless arg.is_a? Hash
      raise ArgumentError, 'Argument is not a Hash'
    end

    @length = {
      value:arg[:length] || 0,
      name:   'Länge',
      short_name: 'Länge',
      type: '^[1-9]\d{,3}(?:(?:,|\.)\d{1,2})?$',
      err_msg:  'Länge in Meter von 1 bis 9999 angeben.',
      source: :local
    }

    @beam = {
      value:  arg[:beam] || 0,
      name:   'Breite',
      short_name: 'Breite',
      type: '^[1-9]\d{,2}(?:(?:,|\.)\d{1,2})?$',
      err_msg:  'Breite in Meter von 1 bis 999 angeben.',
      source: :local
    }

    @height = {
      value:  arg[:height] || 0,
      name:   'Höhe',
      short_name: 'Höhe',
      type: '^[1-9]\d{,2}(?:(?:,|\.)\d{1,2})?$',
      err_msg:  'Höhe in Meter von 1 bis 999 angeben.',
      source: :local
    }

    @mass = {
      value:  arg[:mass] || 0,
      name:   'Masse',
      short_name: 'Masse',
      type: '^[1-9]\d{,6}(?:(?:,|\.)\d{1,2})?$',
      err_msg:  'Masse in Kilogramm von 1 bis 9999999 angeben.',
      source: :local
    }

    #@size

    #@min_crew
    #@max_crew
    #@cargo
    #@scm_speed
    #@ab_speed

    #@weapons
    #@turrets
    #@missiles
  end

  def length?
    @length[:value]
  end

  def length(l)
    unless l.to_s =~ /#{@length[:type]}/
      raise ArgumentError, @length[:err_msg]
    end

    @length[:value] = l
  end

  def beam?
    @beam[:value]
  end

  def beam(b)
    unless b.to_s =~ /#{@beam[:type]}/
      raise ArgumentError, @beam[:err_msg]
    end

    @beam[:value] = b
  end

  def height?
    @height[:value]
  end

  def height(h)
    unless h.to_s =~ /#{@height[:type]}/
      raise ArgumentError, @height[:err_msg]
    end

    @height[:value] = h
  end

  def mass?
    @mass[:value]
  end

  def mass(m)
    unless m.to_s =~ /#{@mass[:type]}/
      raise ArgumentError, @mass[:err_msg]
    end

    @mass[:value] = m
  end

  def formatter
    <<~HEREDOC
      *BETA* Schiffsdaten:
      Länge: #{self.length?} m\tBreite: #{self.beam?} m\tHöhe: #{self.height?} m\tMasse: #{self.mass?} kg
      Crew mind.: 3\tmax.: 5
    HEREDOC
  end

  # fuellt schiffsobjekt mit attributen
  def fill(targs)

    # nach passender variable suchen..
    self.instance_variables.each do |iv|

      # ..die attribut und wert aufnehmen kann
      if eval(iv.to_s)[:short_name].downcase == targs[0].downcase
        method = iv.to_s.tr('@', '')
        self.send method, targs[1]
      end
    end
  end

end
