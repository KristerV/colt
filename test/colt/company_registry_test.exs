defmodule Colt.CompanyRegistryTest do
  use ExUnit.Case, async: true

  alias Colt.CompanyRegistry

  describe "link/1 for Estonia" do
    test "builds a Teatmik link from the registry code" do
      assert %{label: "Teatmik", url: url} =
               CompanyRegistry.link(%{market: :ee, registry_code: "14265185"})

      assert url == "https://www.teatmik.ee/en/personlegal/14265185"
    end
  end

  describe "link/1 per market" do
    test "every configured market embeds the registry code in its url" do
      cases = [
        {:ee, "14265185", "Teatmik", "https://www.teatmik.ee/en/personlegal/14265185"},
        {:fi, "0112038-9", "Asiakastieto",
         "https://www.asiakastieto.fi/yritykset/fi/-/01120389/yleiskuva"},
        {:lv, "40003245752", "Firmas.lv", "https://www.firmas.lv/en/companies/c/40003245752"},
        {:lt, "123033512", "Scoris", "https://scoris.lt/en/imone/123033512"},
        {:se, "5560125790", "Allabolag", "https://www.allabolag.se/5560125790"},
        {:no, "923609016", "Purehelp", "https://www.purehelp.no/company/details/923609016"},
        {:dk, "22756214", "eStatistik", "https://estatistik.dk/virksomhed/c/22756214"},
        {:pl, "0000006865", "BizRaport", "https://www.bizraport.pl/krs/0000006865"}
      ]

      for {market, code, label, url} <- cases do
        assert CompanyRegistry.link(%{market: market, registry_code: code}) ==
                 %{label: label, url: url}
      end
    end
  end

  describe "link/1 edge cases" do
    test "returns nil for an unknown market" do
      assert CompanyRegistry.link(%{market: :de, registry_code: "1234567"}) == nil
    end

    test "returns nil when the registry code is missing or blank" do
      assert CompanyRegistry.link(%{market: :ee, registry_code: nil}) == nil
      assert CompanyRegistry.link(%{market: :ee, registry_code: ""}) == nil
    end

    test "returns nil for nil input" do
      assert CompanyRegistry.link(nil) == nil
    end
  end
end
