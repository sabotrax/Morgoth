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
  @@ship = {
    length: {
      name: "Länge",
      short_name: "^(?:länge|laenge|lang)$",
      type: '^[1-9]\d{,3}(?:(?:,|\.)\d{1,2})?$',
      err_msg: "Länge in Meter von 1 bis 9999 angeben.",
    },
    beam: {
      name: "Breite",
      short_name: "^(?:breite|breit)$",
      type: '^[1-9]\d{,2}(?:(?:,|\.)\d{1,2})?$',
      err_msg: "Breite in Meter von 1 bis 999 angeben.",
    },
    height: {
      name: "Höhe",
      short_name: "^(?:höhe|hoehe|hoch)$",
      type: '^[1-9]\d{,2}(?:(?:,|\.)\d{1,2})?$',
      err_msg: "Höhe in Meter von 1 bis 999 angeben.",
    },
    mass: {
      name: "Masse",
      short_name: "^(?:masse|gewicht|schwer)$",
      type: '^[1-9]\d{,6}(?:(?:,|\.)\d{1,2})?$',
      err_msg: "Masse in Kilogramm von 1 bis 9999999 angeben.",
      source: :local,
    },
    size: {
      name: "Größe",
      short_name: "^(?:größe|groesse|groß)$",
      type: "^(?:(?:K|k)lein|(?:M|m)ittel|(:?G|g)roß|(?:C|c)apital)$",
      err_msg: "Größe angeben in Klein, Mittel, Groß oder Capital.",
      source: :local,
    },
    min_crew: {
      name: "mind. Crew",
      short_name: '^(?:mind\.? crew|mincrew|mindestcrew)$',
      type: '^[1-9]\d{,2}$',
      err_msg: "Crew in Personen von 1 bis 999 angeben.",
      source: :local,
    },
    max_crew: {
      name: "max. Crew",
      short_name: '^(?:max\.? crew|maxcrew|maximalcrew)$',
      type: '^[1-9]\d{,2}$',
      err_msg: "Crew in Personen von 1 bis 999 angeben.",
      source: :local,
    },
    cargo: {
      name: "Fracht",
      short_name: "^(?:fracht|cargo)$",
      type: '^[1-9]\d{,4}$',
      err_msg: "Fracht in SCU von 1 bis 99999 angeben.",
      source: :local,
    },
    scm_speed: {
      name: "SCM",
      short_name: "^scm$",
      type: '^[1-9]\d{,2}$',
      err_msg: "SCM in ms/s von 1 bis 999 angeben.",
      source: :local,
    },
    ab_speed: {
      name: "AB",
      short_name: "^(?:ab|afterburner)$",
      type: '^[1-9]\d{,3}$',
      err_msg: "AB in ms/s von 1 bis 9999 angeben.",
      source: :local,
    },
    weapons: {
      name: "Waffen",
      short_name: "^(?:waffen|hardpoints)$",
      type: '[1-9]\d? S[1-9]\d?(?: (?=\d))?',
      err_msg: 'Waffen so angeben: "4 S3" oder "2 S3 2 S1".',
      source: :local,
    },
    turrets: {
      name: "Türme",
      short_name: "^(?:türme|tuerme|turrets)$",
      type: '[1-9]\d? (?:S)[1-9]\d?(?: (?:à|a|je|je zu|zu je) [1-9]\d?)?',
      err_msg: 'Türme so angeben: "4 S3", "5 S2 à 2" oder "2 S3 2 S1".',
      source: :local,
    },
    missiles: {
      name: "Raketen",
      short_name: "^(?:raketen|torpedos|missiles)$",
      type: '[1-9]\d? (?:S)[1-9]\d?(?: (?:à|a|je|je zu|zu je) [1-9]\d?)?',
      err_msg: 'Raketen so angeben: "4 S3", "3 S3 à 8" oder "2 S3 2 S1".',
      source: :local,
    },
    utility_items: {
      name: "Werkzeugplätze",
      short_name: "^(?:werkzeuge|utily items)$",
      type: '[1-9]\d? S[1-9]\d?(?: (?=\d))?',
      err_msg: 'Werkzeuge so angeben: "4 S3" oder "2 S3 2 S1".',
      source: :local,
    },
  }

  def initialize(arg = {})
    unless arg.is_a? Hash
      raise ArgumentError, "Argument is not a Hash"
    end

    @length = {
      value: arg[:length] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @beam = {
      value: arg[:beam] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @height = {
      value: arg[:height] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @mass = {
      value: arg[:mass] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @size = {
      value: arg[:size] || "Klein",
      source: arg[:source]&.to_sym || :local,
    }

    @min_crew = {
      value: arg[:min_crew] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @max_crew = {
      value: arg[:max_crew] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @cargo = {
      value: arg[:cargo] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @scm_speed = {
      value: arg[:scm_speed] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @ab_speed = {
      value: arg[:ab_speed] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @weapons = {
      value: arg[:weapons] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @turrets = {
      value: arg[:turrets] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @missiles = {
      value: arg[:missiles] || 0,
      source: arg[:source]&.to_sym || :local,
    }

    @utility_items = {
      value: arg[:utility_items] || 0,
      source: arg[:source]&.to_sym || :local,
    }
  end

  def length?
    @length[:value]
  end

  def length(l)
    unless l.to_s =~ /#{@@ship[:length][:type]}/
      raise ArgumentError, @@ship[:length][:err_msg]
    end

    @length[:value] = l
  end

  def beam?
    @beam[:value]
  end

  def beam(b)
    unless b.to_s =~ /#{@@ship[:beam][:type]}/
      raise ArgumentError, @@ship[:beam][:err_msg]
    end

    @beam[:value] = b
  end

  def height?
    @height[:value]
  end

  def height(h)
    unless h.to_s =~ /#{@@ship[:height][:type]}/
      raise ArgumentError, @@ship[:height][:err_msg]
    end

    @height[:value] = h
  end

  def mass?
    @mass[:value]
  end

  def mass(m)
    unless m.to_s =~ /#{@@ship[:mass][:type]}/
      raise ArgumentError, @@ship[:mass][:err_msg]
    end

    @mass[:value] = m
  end

  def size?
    @size[:value]
  end

  def size(s)
    unless s.to_s =~ /#{@@ship[:size][:type]}/
      raise ArgumentError, @@ship[:size][:err_msg]
    end

    @size[:value] = s.capitalize
  end

  def min_crew?
    @min_crew[:value]
  end

  def min_crew(c)
    unless c.to_s =~ /#{@@ship[:min_crew][:type]}/
      raise ArgumentError, @@ship[:min_crew][:err_msg]
    end

    @min_crew[:value] = c
  end

  def max_crew?
    @max_crew[:value]
  end

  def max_crew(c)
    unless c.to_s =~ /#{@@ship[:max_crew][:type]}/
      raise ArgumentError, @@ship[:max_crew][:err_msg]
    end

    @max_crew[:value] = c
  end

  def cargo?
    @cargo[:value]
  end

  def cargo(c)
    unless c.to_s =~ /#{@@ship[:cargo][:type]}/
      raise ArgumentError, @@ship[:cargo][:err_msg]
    end

    @cargo[:value] = c
  end

  def scm_speed?
    @scm_speed[:value]
  end

  def scm_speed(s)
    unless s.to_s =~ /#{@@ship[:scm_speed][:type]}/
      raise ArgumentError, @@ship[:scm_speed][:err_msg]
    end

    @scm_speed[:value] = s
  end

  def ab_speed?
    @ab_speed[:value]
  end

  def ab_speed(s)
    unless s.to_s =~ /#{@@ship[:ab_speed][:type]}/
      raise ArgumentError, @@ship[:ab_speed][:err_msg]
    end

    @ab_speed[:value] = s
  end

  def weapons?
    @weapons[:value]
  end

  def weapons(w)
    unless w.to_s =~ /#{@@ship[:weapons][:type]}/
      raise ArgumentError, @@ship[:weapons][:err_msg]
    end

    @weapons[:value] = w
  end

  def turrets?
    @turrets[:value]
  end

  def turrets(t)
    tgroups = t.split(/(#{@@ship[:turrets][:type]})/)
    tgroups.each do |g|
      next if g.to_s =~ /^(\s|\t)?$/
      unless g.to_s =~ /#{@@ship[:turrets][:type]}/
        raise ArgumentError, @@ship[:turrets][:err_msg]
      end
    end

    t.tr!("s", "S")
    t.gsub!(/(à|a|je zu|zu je|je)/, "à")

    @turrets[:value] = t
  end

  def missiles?
    @missiles[:value]
  end

  def missiles(m)
    mgroups = m.split(/(#{@@ship[:missiles][:type]})/)
    mgroups.each do |g|
      next if g.to_s =~ /^(\s|\t)?$/
      unless g.to_s =~ /#{@@ship[:missiles][:type]}/
        raise ArgumentError, @@ship[:missiles][:err_msg]
      end
    end

    m.tr!("s", "S")
    m.gsub!(/(à|a|je zu|zu je|je)/, "à")

    @missiles[:value] = m
  end

  def utility_items?
    @utility_items[:value]
  end

  def utility_items(i)
    unless i.to_s =~ /#{@@ship[:utility_items][:type]}/
      raise ArgumentError, @@ship[:utility_items][:err_msg]
    end

    @utility_items[:value] = i
  end

  def formatter
    <<~HEREDOC
      Schiffsdaten:
      Größe: #{self.size?}
      Länge: #{self.length?} m\tBreite: #{self.beam?} m\tHöhe: #{self.height?} m\tMasse: #{self.mass?} kg
      Crew mind.: #{self.min_crew?}\tmax.: #{self.max_crew?}\tFracht: #{self.cargo?} SCU
      SCM: #{self.scm_speed?} m/s\tAB: #{self.ab_speed?} m/s
      Waffen: #{self.weapons?}\tTürme: #{self.turrets?}\tRaketen: #{self.missiles?}\tWerkzeugplätze: #{self.utility_items?}
    HEREDOC
  end

  # fuellt schiffsobjekt mit attributen
  def fill(targs)

    # nach passender variable suchen..
    attribute = false
    self.instance_variables.each do |iv|
      iv_literal = iv.to_s.tr("@", "")
      targs.each { |token| token.delete! '"' }
      if @@ship.has_key?(iv_literal.to_sym) and targs[0] =~ /#{@@ship[iv_literal.to_sym][:short_name]}/i
        raise ArgumentError, "Fehlerhafter Aufruf." unless targs[1]
        self.send iv_literal, targs[1]
        attribute = true
      end
    end

    raise TemplateArgumentError, "Eigenschaft unbekannt." unless attribute
  end
end
