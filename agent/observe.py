"""Step 4: Observe — report what the agent decided and did."""


def report(perceived: dict, classification: dict, plan: dict, move_result: dict = None) -> None:
    print("=" * 60)
    print("PERCEIVE")
    print(f"  file:        {perceived['filename']}")
    print(f"  chars read:  {perceived['char_count']}")
    print()
    print("REASON (Gemini)")
    print(f"  ownership:   {classification['ownership']}")
    print(f"  category:    {classification['category']}")
    print(f"  doc_type:    {classification['doc_type']}")
    print(f"  title:       {classification['title']}")
    print(f"  confidence:  {classification['confidence']}")
    print(f"  reasoning:   {classification['reasoning']}")
    print()
    print("ACT (filename-nomenclature skill)")
    print(f"  new name:    {plan['dest_filename']}")
    print(f"  dest dir:    {plan['dest_dir']}")
    if move_result:
        status = move_result.get("status")
        print(f"  move:        {status} -> {move_result.get('dest_path')}")
    else:
        print("  move:        pending (executed by orchestrator via filesystem MCP)")
    print("=" * 60)
