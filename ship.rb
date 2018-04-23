#
# Morgoth
# A Discord bot for Star Citizen

# Copyright 2018 marcus@dankesuper.de

# This file is part of Morgoth.

# Morgoth is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Morgoth is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with Morgoth.  If not, see <http://www.gnu.org/licenses/>.
#

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
      Größe: Mittel
      Länge: #{self.length?} m\tBreite: #{self.beam?} m\tHöhe: #{self.height?} m\tMasse: #{self.mass?} kg
      Crew mind.: 2\tmax.: 2\tFracht: 46 SCU
      SCM: 170 m/s\tAB: 1113 m/s
      Waffen: 4 S3\tTürme: 1 S3\tRaketen: 6 S4\tWerkzeuge: 1
    HEREDOC
  end

  # fuellt schiffsobjekt mit attributen
  def fill(targs)

    # nach passender variable suchen..
    attribute = false
    self.instance_variables.each do |iv|

      # ..die attribut und wert aufnehmen kann
      if eval(iv.to_s)[:short_name].downcase == targs[0].downcase
        method = iv.to_s.tr('@', '')
        self.send method, targs[1]
        attribute = true
      end

    end

    raise TemplateArgumentError, 'Eigenschaft unbekannt.' unless attribute
  end

end
