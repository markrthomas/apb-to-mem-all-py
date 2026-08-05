// -----------------------------------------------------------------------------
// apb_env : agent + scoreboard, with the monitor's analysis port wired to the
// scoreboard — matching tb/apb_components.py ApbEnv.
// -----------------------------------------------------------------------------
class apb_env extends uvm_env;
    `uvm_component_utils(apb_env)

    apb_agent      agent;
    apb_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = apb_agent::type_id::create("agent", this);
        scoreboard = apb_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
