defmodule Colt.Services.EmailAccount.ImportMailboxesTest do
  use ExUnit.Case, async: true

  alias Colt.Services.EmailAccount.ImportMailboxes

  describe "IMAP / mailpool.io export" do
    @imap_csv """
    "Email","First Name","Last Name","IMAP Username","IMAP Password","IMAP Host","IMAP Port","SMTP Username","SMTP Password","SMTP Host","SMTP Port","Daily Limit","Warmup Enabled","Warmup Limit","Warmup Increment"
    "robert@liidid.ee","Robert","Kuusk","robert@liidid.ee","secret1","imap.mailpool.io",993,"robert@liidid.ee","secret1","smtp.mailpool.io",465,30,true,20,2
    "krister@liidid.ee","Krister","Viirsaar","krister@liidid.ee","secret2","imap.mailpool.io",993,"krister@liidid.ee","secret2","smtp.mailpool.io",465,30,true,20,2
    """

    test "imports the display name from First + Last" do
      assert {:ok, [robert, krister]} = ImportMailboxes.run(@imap_csv)

      assert robert.address == "robert@liidid.ee"
      assert robert.display_name == "Robert Kuusk"
      assert krister.display_name == "Krister Viirsaar"
    end

    test "carries IMAP/SMTP settings" do
      {:ok, [robert | _]} = ImportMailboxes.run(@imap_csv)

      assert robert.settings["imap_host"] == "imap.mailpool.io"
      assert robert.settings["imap_port"] == 993
      assert robert.settings["smtp_host"] == "smtp.mailpool.io"
      assert robert.settings["smtp_port"] == 465
    end

    test "leaves display_name nil when both name columns are blank" do
      csv = """
      "Email","First Name","Last Name","IMAP Username","IMAP Password","IMAP Host","IMAP Port","SMTP Username","SMTP Password","SMTP Host","SMTP Port"
      "noname@liidid.ee","","","noname@liidid.ee","s","imap.mailpool.io",993,"noname@liidid.ee","s","smtp.mailpool.io",465
      """

      assert {:ok, [box]} = ImportMailboxes.run(csv)
      assert box.display_name == nil
    end
  end

  describe "Google Workspace export" do
    @google_csv """
    "Email Service Provider","Email","Password","App Password","Secret","Admin Email","Admin Password","Admin Secret"
    "GoogleWorkspace","siim@liids.ee","plainpw","apppw","sec","siim@liids.ee","plainpw","sec"
    """

    test "imports with no display name (CSV has no name columns)" do
      assert {:ok, [siim]} = ImportMailboxes.run(@google_csv)

      assert siim.address == "siim@liids.ee"
      assert siim.display_name == nil
    end

    test "uses the app password and Gmail IMAP host" do
      {:ok, [siim]} = ImportMailboxes.run(@google_csv)

      assert siim.settings["imap_host"] == "imap.gmail.com"
      assert siim.settings["imap_password"] == "apppw"
      assert siim.settings["smtp_host"] == "smtp.gmail.com"
    end
  end

  describe "errors" do
    test "unknown format" do
      assert {:error, :unknown_format} = ImportMailboxes.run("\"Foo\",\"Bar\"\n1,2\n")
    end

    test "empty input" do
      assert {:error, :empty} = ImportMailboxes.run("")
    end
  end
end
