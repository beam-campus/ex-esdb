
defmodule GenerateSupervisionTree do
  def run do
    # Start the application
    {:ok, _} = Application.ensure_all_started(:ex_esdb)

    # Find the top supervisor
    top_supervisor_pid = Process.whereis(ExESDB.System)

    if top_supervisor_pid do
      # Generate the dot file
      dot_file_content = generate_dot(top_supervisor_pid)

      # Write the dot file
      File.write!("supervision_tree.dot", dot_file_content)

      # Convert dot to svg
      System.cmd("dot", ["-Tsvg", "supervision_tree.dot", "-o", "design_docs/supervision_tree.svg"])
    else
      IO.puts "Could not find the top supervisor"
    end
  end

  defp generate_dot(supervisor_pid) do
    """
digraph G {
  rankdir=LR;
  #{generate_body(supervisor_pid)}
}
"""
  end

  defp generate_body(supervisor_pid) do
    supervisor_name = inspect(supervisor_pid)
    children = Supervisor.which_children(supervisor_pid)

    Enum.map(children, fn {_, child_pid, type, modules} ->
      child_name = case modules do
        [module] -> inspect(module)
        _ -> inspect(child_pid)
      end
      edge = "\"#{supervisor_name}\" -> \"#{child_name}\”;\n"
      if type == :supervisor do
        edge <> generate_body(child_pid)
      else
        edge
      end
    end)
    |> Enum.join()
  end
end

GenerateSupervisionTree.run()
