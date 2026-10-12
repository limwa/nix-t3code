# Checks that the desktop app starts its backend and renders the GUI.
{ t3code }:

{
  name = "${t3code.pname}-desktop";

  nodes.machine =
    { modulesPath, ... }:
    {
      imports = [
        (modulesPath + "/../tests/common/user-account.nix")
        (modulesPath + "/../tests/common/x11.nix")
      ];

      test-support.displayManager.auto.user = "alice";
      environment.systemPackages = [ t3code ];

      virtualisation.memorySize = 4096;
      virtualisation.cores = 2;
    };

  enableOCR = true;

  testScript = ''
    start_all()
    machine.wait_for_x()
    machine.wait_for_file("/home/alice/.Xauthority")
    machine.succeed("xauth merge ~alice/.Xauthority")

    machine.execute("su - alice -c 'DISPLAY=:0 t3code-desktop >&2 &'")

    machine.wait_for_window("T3 Code")

    # The onboarding screen lists the local backend once the client has
    # connected to it, which needs the backend to have started successfully.
    machine.wait_for_text("Connect your computers")
    machine.wait_for_text("Connected")
    machine.screenshot("desktop")
  '';
}
