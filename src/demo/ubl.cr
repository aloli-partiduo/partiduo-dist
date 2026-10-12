# SPDX-License-Identifier: AGPL-3.0-or-later

require "html"

module PartiduoDist
  module Demo
    # Facture UBL 2.1 (EN 16931) d'un fournisseur fictif, adressée au
    # dossier, déposée sur la plateforme agréée simulée.
    module Ubl
      extend self

      record Line, label : String, quantity : BigDecimal, price : BigDecimal, unit : String

      def invoice(number : String, day : Time, rate : BigDecimal, note : String, supplier : Format::Tiers,
                  buyer_siren : String, buyer_name : String, lines : Array(Line)) : Bytes
        net = lines.sum(BigDecimal.new(0)) { |line| (line.price * line.quantity).round(2) }
        vat = (net * rate / 100).round(2)
        gross = net + vat
        due = day + 30.days
        siren = supplier.siren.to_s
        vat_id = supplier.tva.to_s
        address = supplier.adresse
        percent = f(rate)
        rows = lines.map_with_index do |line, index|
          <<-XML
            <cac:InvoiceLine>
              <cbc:ID>#{index + 1}</cbc:ID>
              <cbc:InvoicedQuantity unitCode="#{x(line.unit)}">#{line.quantity}</cbc:InvoicedQuantity>
              <cbc:LineExtensionAmount currencyID="EUR">#{f((line.price * line.quantity).round(2))}</cbc:LineExtensionAmount>
              <cac:Item><cbc:Name>#{x(line.label)}</cbc:Name><cac:ClassifiedTaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>#{percent}</cbc:Percent><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:ClassifiedTaxCategory></cac:Item>
              <cac:Price><cbc:PriceAmount currencyID="EUR">#{f(line.price)}</cbc:PriceAmount></cac:Price>
            </cac:InvoiceLine>
            XML
        end
        <<-XML.to_slice
          <?xml version="1.0" encoding="UTF-8"?>
          <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
            <cbc:CustomizationID>urn:cen.eu:en16931:2017</cbc:CustomizationID>
            <cbc:ID>#{x(number)}</cbc:ID>
            <cbc:IssueDate>#{day.to_s("%Y-%m-%d")}</cbc:IssueDate>
            <cbc:DueDate>#{due.to_s("%Y-%m-%d")}</cbc:DueDate>
            <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
            <cbc:Note>#{x(note)}</cbc:Note>
            <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
            <cac:AccountingSupplierParty><cac:Party>
              <cbc:EndpointID schemeID="0225">#{siren}</cbc:EndpointID>
              <cac:PartyName><cbc:Name>#{x(supplier.nom.to_s)}</cbc:Name></cac:PartyName>
              <cac:PostalAddress><cbc:StreetName>#{x(address.try(&.ligne1).to_s)}</cbc:StreetName><cbc:CityName>#{x(address.try(&.ville).to_s)}</cbc:CityName><cbc:PostalZone>#{x(address.try(&.code_postal).to_s)}</cbc:PostalZone><cac:Country><cbc:IdentificationCode>FR</cbc:IdentificationCode></cac:Country></cac:PostalAddress>
              <cac:PartyTaxScheme><cbc:CompanyID>#{x(vat_id)}</cbc:CompanyID><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme>
              <cac:PartyLegalEntity><cbc:RegistrationName>#{x(supplier.nom.to_s)}</cbc:RegistrationName><cbc:CompanyID schemeID="0002">#{siren}</cbc:CompanyID></cac:PartyLegalEntity>
            </cac:Party></cac:AccountingSupplierParty>
            <cac:AccountingCustomerParty><cac:Party>
              <cbc:EndpointID schemeID="0225">#{buyer_siren}</cbc:EndpointID>
              <cac:PartyName><cbc:Name>#{x(buyer_name)}</cbc:Name></cac:PartyName>
              <cac:PostalAddress><cac:Country><cbc:IdentificationCode>FR</cbc:IdentificationCode></cac:Country></cac:PostalAddress>
              <cac:PartyLegalEntity><cbc:RegistrationName>#{x(buyer_name)}</cbc:RegistrationName><cbc:CompanyID schemeID="0002">#{buyer_siren}</cbc:CompanyID></cac:PartyLegalEntity>
            </cac:Party></cac:AccountingCustomerParty>
            <cac:TaxTotal>
              <cbc:TaxAmount currencyID="EUR">#{f(vat)}</cbc:TaxAmount>
              <cac:TaxSubtotal><cbc:TaxableAmount currencyID="EUR">#{f(net)}</cbc:TaxableAmount><cbc:TaxAmount currencyID="EUR">#{f(vat)}</cbc:TaxAmount>
                <cac:TaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>#{percent}</cbc:Percent><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:TaxCategory></cac:TaxSubtotal>
            </cac:TaxTotal>
            <cac:LegalMonetaryTotal>
              <cbc:LineExtensionAmount currencyID="EUR">#{f(net)}</cbc:LineExtensionAmount>
              <cbc:TaxExclusiveAmount currencyID="EUR">#{f(net)}</cbc:TaxExclusiveAmount>
              <cbc:TaxInclusiveAmount currencyID="EUR">#{f(gross)}</cbc:TaxInclusiveAmount>
              <cbc:PayableAmount currencyID="EUR">#{f(gross)}</cbc:PayableAmount>
            </cac:LegalMonetaryTotal>
          #{rows.join("\n")}
          </Invoice>
          XML
      end

      private def f(amount : BigDecimal) : String
        Support.decimal(amount)
      end

      private def x(text : String) : String
        HTML.escape(text)
      end
    end
  end
end
