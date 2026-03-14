use graphviz_anywhere::{Engine, Format, GraphvizContext};

fn main() {
    // Print the library version if available.
    if let Some(ver) = graphviz_anywhere::version() {
        println!("Graphviz version: {ver}");
    }

    // Create a rendering context.
    let ctx = GraphvizContext::new().expect("failed to create graphviz context");

    // A sample DOT graph.
    let dot = r##"
        digraph G {
            rankdir=LR;
            node [shape=box, style="rounded,filled", fillcolor="#E8F4FD"];

            start [label="Start", fillcolor="#90EE90"];
            parse [label="Parse DOT"];
            layout [label="Compute Layout"];
            render [label="Render Output"];
            done [label="Done", fillcolor="#FFB6C1"];

            start -> parse -> layout -> render -> done;
        }
    "##;

    // Render to SVG.
    match ctx.render_to_string(dot, Engine::Dot, Format::Svg) {
        Ok(svg) => {
            println!("SVG output ({} bytes):", svg.len());
            println!("{svg}");
        }
        Err(e) => {
            eprintln!("render failed: {e}");
            std::process::exit(1);
        }
    }
}
