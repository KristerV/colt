defmodule Colt.Services.Enrichment.ContactRungsTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Enrichment.ContactRungs

  defp campaign(opts) do
    %{
      reach_owner?: Keyword.get(opts, :owner, false),
      reach_title?: Keyword.get(opts, :title, false),
      reach_generic?: Keyword.get(opts, :generic, false)
    }
  end

  describe "first/1" do
    test "picks the highest enabled rung, in ladder order" do
      assert ContactRungs.first(campaign(owner: true, title: true, generic: true)) == :owner
      assert ContactRungs.first(campaign(title: true, generic: true)) == :title
      assert ContactRungs.first(campaign(generic: true)) == :generic
    end

    test "the ladder order is fixed regardless of which rungs are on" do
      assert ContactRungs.first(campaign(owner: true, generic: true)) == :owner
    end

    test "no rungs enabled means nothing to try" do
      assert ContactRungs.first(campaign([])) == :none
    end
  end

  describe "after_rung/2" do
    test "walks forward to the next enabled rung" do
      c = campaign(owner: true, title: true, generic: true)
      assert ContactRungs.after_rung(c, :owner) == :title
      assert ContactRungs.after_rung(c, :title) == :generic
      assert ContactRungs.after_rung(c, :generic) == :none
    end

    test "skips disabled rungs rather than stopping at them" do
      c = campaign(owner: true, generic: true)
      assert ContactRungs.after_rung(c, :owner) == :generic
    end

    test "never walks backwards — a missed title does not retry the owner" do
      c = campaign(owner: true, title: true)
      assert ContactRungs.after_rung(c, :title) == :none
    end

    test "the last rung always ends the ladder" do
      c = campaign(owner: true, title: true, generic: true)
      assert ContactRungs.after_rung(c, :generic) == :none
    end
  end
end
