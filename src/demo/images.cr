# SPDX-License-Identifier: AGPL-3.0-or-later

require "compress/zlib"
require "digest/crc32"

module PartiduoDist
  module Demo
    # Images de justificatifs générées (tickets de caisse, notes de frais) :
    # PNG en couleurs vraies, texte en police matricielle 5 × 7 agrandie.
    # Aucune image n'est tirée d'un fichier : tout est dessiné ici.
    class Receipt
      # Police 5 × 7 : une colonne par octet, bit de poids faible en haut.
      FONT = {
        'A' => {0x7C, 0x12, 0x11, 0x12, 0x7C}, 'B' => {0x7F, 0x49, 0x49, 0x49, 0x36},
        'C' => {0x3E, 0x41, 0x41, 0x41, 0x22}, 'D' => {0x7F, 0x41, 0x41, 0x22, 0x1C},
        'E' => {0x7F, 0x49, 0x49, 0x49, 0x41}, 'F' => {0x7F, 0x09, 0x09, 0x09, 0x01},
        'G' => {0x3E, 0x41, 0x49, 0x49, 0x7A}, 'H' => {0x7F, 0x08, 0x08, 0x08, 0x7F},
        'I' => {0x00, 0x41, 0x7F, 0x41, 0x00}, 'J' => {0x20, 0x40, 0x41, 0x3F, 0x01},
        'K' => {0x7F, 0x08, 0x14, 0x22, 0x41}, 'L' => {0x7F, 0x40, 0x40, 0x40, 0x40},
        'M' => {0x7F, 0x02, 0x0C, 0x02, 0x7F}, 'N' => {0x7F, 0x04, 0x08, 0x10, 0x7F},
        'O' => {0x3E, 0x41, 0x41, 0x41, 0x3E}, 'P' => {0x7F, 0x09, 0x09, 0x09, 0x06},
        'Q' => {0x3E, 0x41, 0x51, 0x21, 0x5E}, 'R' => {0x7F, 0x09, 0x19, 0x29, 0x46},
        'S' => {0x46, 0x49, 0x49, 0x49, 0x31}, 'T' => {0x01, 0x01, 0x7F, 0x01, 0x01},
        'U' => {0x3F, 0x40, 0x40, 0x40, 0x3F}, 'V' => {0x1F, 0x20, 0x40, 0x20, 0x1F},
        'W' => {0x3F, 0x40, 0x38, 0x40, 0x3F}, 'X' => {0x63, 0x14, 0x08, 0x14, 0x63},
        'Y' => {0x07, 0x08, 0x70, 0x08, 0x07}, 'Z' => {0x61, 0x51, 0x49, 0x45, 0x43},
        '0' => {0x3E, 0x51, 0x49, 0x45, 0x3E}, '1' => {0x00, 0x42, 0x7F, 0x40, 0x00},
        '2' => {0x42, 0x61, 0x51, 0x49, 0x46}, '3' => {0x21, 0x41, 0x45, 0x4B, 0x31},
        '4' => {0x18, 0x14, 0x12, 0x7F, 0x10}, '5' => {0x27, 0x45, 0x45, 0x45, 0x39},
        '6' => {0x3C, 0x4A, 0x49, 0x49, 0x30}, '7' => {0x01, 0x71, 0x09, 0x05, 0x03},
        '8' => {0x36, 0x49, 0x49, 0x49, 0x36}, '9' => {0x06, 0x49, 0x49, 0x29, 0x1E},
        ',' => {0x00, 0x50, 0x30, 0x00, 0x00}, '.' => {0x00, 0x60, 0x60, 0x00, 0x00},
        ':' => {0x00, 0x36, 0x36, 0x00, 0x00}, '-' => {0x08, 0x08, 0x08, 0x08, 0x08},
        '/' => {0x20, 0x10, 0x08, 0x04, 0x02}, '%' => {0x23, 0x13, 0x08, 0x64, 0x62},
        '*' => {0x14, 0x08, 0x3E, 0x08, 0x14}, '=' => {0x14, 0x14, 0x14, 0x14, 0x14},
      }

      alias Color = {UInt8, UInt8, UInt8}

      PAPER  = {250_u8, 248_u8, 240_u8}
      INK    = {40_u8, 40_u8, 48_u8}
      FAINT  = {150_u8, 150_u8, 160_u8}
      BORDER = {205_u8, 200_u8, 190_u8}

      getter width : Int32
      getter height : Int32

      def initialize(@width : Int32, @height : Int32, background : Color = PAPER)
        @pixels = Bytes.new(@width * @height * 3)
        fill(0, 0, @width, @height, background)
      end

      def fill(x : Int32, y : Int32, w : Int32, h : Int32, color : Color) : Nil
        (y...(y + h)).each do |row|
          next unless 0 <= row < @height
          (x...(x + w)).each do |column|
            next unless 0 <= column < @width
            offset = (row * @width + column) * 3
            @pixels[offset] = color[0]
            @pixels[offset + 1] = color[1]
            @pixels[offset + 2] = color[2]
          end
        end
      end

      # Texte en majuscules sans accents, `scale` pixels par point.
      def text(x : Int32, y : Int32, value : String, scale : Int32 = 3, color : Color = INK) : Nil
        cursor = x
        Receipt.plain(value).each_char do |char|
          if glyph = FONT[char]?
            glyph.each_with_index do |column, index|
              7.times do |row|
                fill(cursor + index * scale, y + row * scale, scale, scale, color) if column.bit(row) == 1
              end
            end
          end
          cursor += 6 * scale
        end
      end

      # Texte aligné à droite sur `right`.
      def text_right(right : Int32, y : Int32, value : String, scale : Int32 = 3, color : Color = INK) : Nil
        text(right - Receipt.plain(value).size * 6 * scale, y, value, scale, color)
      end

      def dashes(y : Int32) : Nil
        x = 20
        while x < @width - 20
          fill(x, y, 8, 2, FAINT)
          x += 14
        end
      end

      # Majuscules, accents retirés (police sans diacritiques).
      def self.plain(value : String) : String
        value.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").upcase.tr("’'«»", "    ")
      end

      # Fichier PNG (couleurs vraies, sans filtre).
      def png : Bytes
        io = IO::Memory.new
        io.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        header = IO::Memory.new
        header.write_bytes(@width.to_u32, IO::ByteFormat::BigEndian)
        header.write_bytes(@height.to_u32, IO::ByteFormat::BigEndian)
        header.write(Bytes[8, 2, 0, 0, 0])
        chunk(io, "IHDR", header.to_slice)
        raw = IO::Memory.new
        Compress::Zlib::Writer.open(raw) do |zlib|
          @height.times do |row|
            zlib.write_byte(0_u8)
            zlib.write(@pixels[row * @width * 3, @width * 3])
          end
        end
        chunk(io, "IDAT", raw.to_slice)
        chunk(io, "IEND", Bytes.empty)
        io.to_slice
      end

      private def chunk(io : IO, type : String, data : Bytes) : Nil
        io.write_bytes(data.size.to_u32, IO::ByteFormat::BigEndian)
        body = IO::Memory.new
        body.write(type.to_slice)
        body.write(data)
        io.write(body.to_slice)
        io.write_bytes(Digest::CRC32.checksum(body.to_slice), IO::ByteFormat::BigEndian)
      end

      # Ticket de caisse : enseigne (bandeau de couleur), adresse, lignes
      # (libellé, montant), total TTC, TVA, date et moyen de paiement.
      def self.ticket(shop : String, address : String, lines : Array({String, String}), total : String,
                      vat : String, day : Time, method : String, color : Color) : Bytes
        height = 330 + lines.size * 34
        image = new(420, height)
        image.fill(0, 0, 420, height, BORDER)
        image.fill(4, 4, 412, height - 8, PAPER)
        image.fill(4, 4, 412, 70, color)
        image.text(24, 22, shop, 4, {255_u8, 255_u8, 255_u8})
        image.text(24, 90, address, 2, FAINT)
        image.text(24, 116, day.to_s("%d/%m/%Y 10:%M"), 2, FAINT)
        image.dashes(146)
        y = 166
        lines.each do |(label, amount)|
          image.text(24, y, label, 3)
          image.text_right(396, y, amount, 3)
          y += 34
        end
        image.dashes(y + 4)
        image.text(24, y + 24, "TOTAL TTC", 3)
        image.text_right(396, y + 24, "#{total} EUR", 3)
        image.text(24, y + 72, "DONT TVA #{vat} EUR", 2, FAINT)
        image.text(24, y + 98, "PAIEMENT #{method}", 2, FAINT)
        image.text(24, y + 124, "MERCI DE VOTRE VISITE", 2, FAINT)
        image.png
      end

      # Facture reçue d'un fournisseur (copie numérisée) : en-tête du
      # fournisseur, numéro et date, client (`buyer`), lignes, totaux HT,
      # TVA et TTC.
      def self.invoice(supplier : String, address : String, number : String, day : Time, lines : Array({String, String}),
                       net : String, vat : String, gross : String, color : Color, buyer : String) : Bytes
        height = 420 + lines.size * 30
        image = new(520, height, {255_u8, 255_u8, 255_u8})
        image.fill(0, 0, 520, 12, color)
        image.text(24, 32, supplier, 3, color)
        image.text(24, 64, address, 2, FAINT)
        image.text(24, 104, "FACTURE #{number}", 3)
        image.text(24, 134, "DU #{day.to_s("%d/%m/%Y")}", 2, FAINT)
        image.text(24, 158, buyer, 2, FAINT)
        image.fill(24, 190, 472, 2, color)
        y = 206
        lines.each do |(label, amount)|
          image.text(24, y, label[0, 30], 2)
          image.text_right(496, y, amount, 2)
          y += 30
        end
        image.fill(24, y + 6, 472, 2, color)
        image.text(24, y + 26, "TOTAL HT", 2)
        image.text_right(496, y + 26, net, 2)
        image.text(24, y + 54, "TVA", 2)
        image.text_right(496, y + 54, vat, 2)
        image.text(24, y + 86, "TOTAL TTC", 3)
        image.text_right(496, y + 86, "#{gross} EUR", 3)
        image.text(24, height - 40, "REGLEMENT A RECEPTION - PENALITES DE RETARD 3 FOIS LE TAUX LEGAL", 1, FAINT)
        image.png
      end
    end
  end
end
