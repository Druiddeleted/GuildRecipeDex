#!/usr/bin/env python3
"""
Generate data/catalog.lua from wago.tools DB2 exports.

Pulls SkillLine, TradeSkillCategory, and SkillLineAbility CSVs from
https://wago.tools/db2/<Table>/csv (latest retail build), joins them, filters
to tradeskill professions only, and emits a Lua data file the addon consumes.

Run from the addon root: `python3 scripts/generate-catalog.py`
"""
import csv
import io
import os
import sys
import urllib.request

OUT_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "catalog.lua")

# Profession base skillLineIDs. Children/expansion variants descend from these.
PROFESSION_BASES = {
    164: "Blacksmithing",
    165: "Leatherworking",
    171: "Alchemy",
    182: "Herbalism",
    185: "Cooking",
    186: "Mining",
    197: "Tailoring",
    202: "Engineering",
    333: "Enchanting",
    356: "Fishing",
    393: "Skinning",
    755: "Jewelcrafting",
    773: "Inscription",
}

BASE_URL = "https://wago.tools/db2/{table}/csv"


UA = "Mozilla/5.0 (GuildRecipeDex catalog generator; +https://github.com/Druiddeleted/GuildRecipeDex)"


def fetch_csv(table):
    url = BASE_URL.format(table=table)
    sys.stderr.write(f"fetching {url}\n")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req) as r:
        text = r.read().decode("utf-8")
    return list(csv.DictReader(io.StringIO(text)))


def to_int(s, default=0):
    try:
        return int(s)
    except (TypeError, ValueError):
        return default


def main():
    skill_lines_rows = fetch_csv("SkillLine")
    categories_rows = fetch_csv("TradeSkillCategory")
    abilities_rows = fetch_csv("SkillLineAbility")
    spell_effects_rows = fetch_csv("SpellEffect")
    crafting_data_rows = fetch_csv("CraftingData")
    spell_reagents_rows = fetch_csv("SpellReagents")
    item_effect_rows = fetch_csv("ItemEffect")
    item_x_item_effect_rows = fetch_csv("ItemXItemEffect")

    # Modern (DF+) Modified Crafting reagent tables.
    mcss_rows = fetch_csv("ModifiedCraftingSpellSlot")
    mcrs_rows = fetch_csv("ModifiedCraftingReagentSlot")
    mcrslot_x_cat_rows = fetch_csv("MCRSlotXMCRCategory")
    mcri_rows = fetch_csv("ModifiedCraftingReagentItem")
    mci_rows = fetch_csv("ModifiedCraftingItem")

    # ----- Modern Modified Crafting reagent join (DF+/Midnight) -----
    # ReagentType enum (per DB2 + Blizzard ProfessionConstants):
    #   0 = Modifying, 1 = Basic (required), 2 = Finishing, 3 = Automatic (server-injected)
    REAGENT_TYPE_NAMES = {0: "modifying", 1: "required", 2: "finishing"}

    # slotID -> reagentType, and slotID -> flags.
    # Sparks are modeled as ReagentType=0 (Modifying) but are mandatory; they
    # carry Flags bit 0x4 to distinguish them from genuinely-optional modifying
    # slots (embellishments, stat amplifiers, crest infusion = Flags 0x2). We
    # promote those to "required" so they show under Reagents, not Optional.
    SLOT_FLAG_REQUIRED = 0x4
    slot_to_type = {}
    slot_to_flags = {}
    for r in mcrs_rows:
        sid = to_int(r.get("ID"))
        slot_to_type[sid] = to_int(r.get("ReagentType"))
        slot_to_flags[sid] = to_int(r.get("Flags"))

    # slotID -> ordered list of categoryIDs
    slot_to_cats = {}
    for r in mcrslot_x_cat_rows:
        slot_id = to_int(r.get("ModifiedCraftingReagentSlotID"))
        cat = to_int(r.get("ModifiedCraftingCategoryID"))
        order = to_int(r.get("_Order"))
        slot_to_cats.setdefault(slot_id, []).append((order, cat))
    for slot_id, lst in slot_to_cats.items():
        lst.sort()
        slot_to_cats[slot_id] = [c for _, c in lst]

    # MCRItem ID -> categoryID
    mcri_to_cat = {}
    for r in mcri_rows:
        mcri_to_cat[to_int(r.get("ID"))] = to_int(r.get("ModifiedCraftingCategoryID"))

    # category -> list of itemIDs (concrete items, all quality tiers grouped)
    cat_to_items = {}
    for r in mci_rows:
        mcri_id = to_int(r.get("ModifiedCraftingReagentItemID"))
        item = to_int(r.get("ItemID"))
        if not mcri_id or not item:
            continue
        cat = mcri_to_cat.get(mcri_id)
        if cat:
            cat_to_items.setdefault(cat, []).append(item)
    # de-dupe while preserving order
    for cat, items in cat_to_items.items():
        seen = set()
        deduped = []
        for it in items:
            if it not in seen:
                seen.add(it)
                deduped.append(it)
        cat_to_items[cat] = deduped

    # Some optional slots consume a CURRENCY, not an item (e.g. the "Infuse with
    # Power" crest slot on epic crafted gear). Those reagent categories carry no
    # ModifiedCraftingItem rows, so the item join below yields nothing and the
    # slot would be dropped. The category->currency link isn't in DB2, so map it
    # explicitly here. IDs are currencyIDs; the addon renders them via
    # C_CurrencyInfo. Keep this updated as new seasons add crest categories.
    CURRENCY_CATEGORIES = {
        901: [3345, 3347],  # 12.0 S1 Crests (Epic): Hero Dawncrest, Myth Dawncrest
    }

    # spellID -> { required: [(qty, [ids], is_currency)], modifying: [...], finishing: [...] }
    modern_reagents = {}
    for r in mcss_rows:
        spell = to_int(r.get("SpellID"))
        slot_id = to_int(r.get("ModifiedCraftingReagentSlotID"))
        qty = to_int(r.get("ReagentCount"))
        if not spell or not slot_id:
            continue
        rtype = slot_to_type.get(slot_id)
        if rtype is None:
            continue
        if rtype == 0 and (slot_to_flags.get(slot_id, 0) & SLOT_FLAG_REQUIRED):
            bucket_name = "required"  # Spark: mandatory despite Modifying type
        else:
            bucket_name = REAGENT_TYPE_NAMES.get(rtype)
        if not bucket_name:
            continue  # skip Automatic (3) and unknown
        items = []
        is_currency = False
        for cat in slot_to_cats.get(slot_id, []):
            if cat in CURRENCY_CATEGORIES:
                items.extend(CURRENCY_CATEGORIES[cat])
                is_currency = True
            else:
                items.extend(cat_to_items.get(cat, []))
        if not items:
            continue
        slot_data = modern_reagents.setdefault(spell, {"required": [], "modifying": [], "finishing": []})
        slot_data[bucket_name].append((qty, items, is_currency))

    # Legacy SpellReagents fallback (pre-DF recipes).
    legacy_reagents = {}
    for r in spell_reagents_rows:
        sid = to_int(r.get("SpellID"))
        if not sid:
            continue
        reagents = []
        for i in range(8):
            item = to_int(r.get(f"Reagent_{i}"))
            count = to_int(r.get(f"ReagentCount_{i}"))
            if item and count:
                reagents.append((item, count))
        if reagents:
            legacy_reagents[sid] = reagents

    # CraftingData lookup: ID -> CraftedItemID. Modern (DF+) profession recipes
    # use SpellEffect.Effect=288 where EffectMiscValue_0 references CraftingData.ID,
    # and the actual output item is CraftingData.CraftedItemID.
    crafting_to_item = {}
    for r in crafting_data_rows:
        cid = to_int(r.get("ID"))
        item = to_int(r.get("CraftedItemID"))
        if cid and item:
            crafting_to_item[cid] = item

    # Build spell -> source itemID map via ItemEffect + ItemXItemEffect.
    # ItemEffect.SpellID is the spell taught; ItemXItemEffect links ItemEffect
    # rows to the item (scroll/book) that teaches it. Keep the lowest itemID
    # per spell (quality 1 base item when multiple quality tiers exist).
    effect_to_spell = {}
    for r in item_effect_rows:
        eid = to_int(r.get("ID"))
        spell = to_int(r.get("SpellID"))
        if eid and spell:
            effect_to_spell[eid] = spell

    spell_to_source_item = {}
    for r in item_x_item_effect_rows:
        eid = to_int(r.get("ItemEffectID"))
        item = to_int(r.get("ItemID"))
        spell = effect_to_spell.get(eid)
        if spell and item:
            existing = spell_to_source_item.get(spell)
            if existing is None or item < existing:
                spell_to_source_item[spell] = item

    # Build spell -> output itemID map from SpellEffect.
    # Effect 24  = classic create-item, EffectItemType is itemID directly.
    # Effect 288 = modern (DF+) crafted-item, EffectMiscValue_0 -> CraftingData.ID -> CraftedItemID.
    spell_to_item = {}
    for r in spell_effects_rows:
        eff = to_int(r.get("Effect"))
        sid = to_int(r.get("SpellID"))
        if not sid or sid in spell_to_item:
            continue
        item = 0
        if eff == 24:
            item = to_int(r.get("EffectItemType"))
        elif eff == 288:
            misc = to_int(r.get("EffectMiscValue_0"))
            item = crafting_to_item.get(misc, 0)
        if item:
            spell_to_item[sid] = item

    # Build skill_line: ID -> {name, parentSkillLineID, iconFileID}
    skill_lines = {}
    for r in skill_lines_rows:
        sid = to_int(r["ID"])
        skill_lines[sid] = {
            "id": sid,
            "name": r.get("DisplayName_lang", "") or "",
            "parent": to_int(r["ParentSkillLineID"]),
            "icon": to_int(r["SpellIconFileID"]),
        }

    # Determine which skill lines belong to a tradeskill profession by walking parents.
    def root_profession(sid):
        seen = set()
        cur = sid
        while cur and cur not in seen:
            seen.add(cur)
            if cur in PROFESSION_BASES:
                return cur
            cur = skill_lines.get(cur, {}).get("parent", 0)
        return None

    relevant_sl = {}  # sid -> rootProfessionBaseID
    for sid in skill_lines:
        root = root_profession(sid)
        if root:
            relevant_sl[sid] = root

    # Categories: ID -> {name, parent, skillLine}
    categories = {}
    for r in categories_rows:
        cid = to_int(r["ID"])
        sl = to_int(r["SkillLineID"])
        if sl in relevant_sl:
            categories[cid] = {
                "id": cid,
                "name": r.get("Name_lang", "") or "",
                "parent": to_int(r["ParentTradeSkillCategoryID"]),
                "skillLine": sl,
            }

    # Recipes: from SkillLineAbility, filtered to relevant skill lines.
    # SkillLineAbility has columns: Spell (recipeID), SkillLine, TradeSkillCategoryID
    recipes = {}
    for r in abilities_rows:
        sl = to_int(r["SkillLine"])
        if sl not in relevant_sl:
            continue
        spell = to_int(r["Spell"])
        if spell == 0:
            continue
        # Merge sources: modern Modified Crafting supplies modifying/finishing
        # (and required if present), and legacy SpellReagents fills in required
        # for older recipes that pre-date the modern system.
        merged = {"required": [], "modifying": [], "finishing": []}
        if spell in modern_reagents:
            m = modern_reagents[spell]
            merged["required"].extend(m["required"])
            merged["modifying"].extend(m["modifying"])
            merged["finishing"].extend(m["finishing"])
        if not merged["required"] and spell in legacy_reagents:
            for item, count in legacy_reagents[spell]:
                merged["required"].append((count, [item]))

        recipes[spell] = {
            "spellID": spell,
            "skillLine": sl,
            "category": to_int(r["TradeSkillCategoryID"]),
            "item": spell_to_item.get(spell, 0),
            "reagents": merged,
        }

    # Group expansion-children under their base profession.
    # An "expansion child" is any skill line whose parent is a profession base (or
    # is itself the base when no children — rare for modern profs).
    professions = {}  # baseID -> {name, expansions = {childID: {name, parentBase}}}
    for sid, root in relevant_sl.items():
        sl = skill_lines[sid]
        prof = professions.setdefault(root, {
            "id": root,
            "name": PROFESSION_BASES[root],
            "expansions": {},
        })
        # Treat any descendant of the root as a potential expansion variant.
        if sid != root:
            prof["expansions"][sid] = {
                "id": sid,
                "name": sl["name"] or PROFESSION_BASES[root],
                "icon": sl["icon"],
            }

    # Emit Lua.
    sys.stderr.write(f"writing {OUT_PATH}\n")
    out_dir = os.path.dirname(OUT_PATH)
    os.makedirs(out_dir, exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        f.write("local _, ns = ...\n\n")
        f.write("-- Generated by scripts/generate-catalog.py. Do not edit by hand.\n")
        f.write("-- Source: wago.tools DB2 exports (latest retail build).\n\n")

        f.write("ns.Catalog = {}\n\n")

        # Professions table
        f.write("ns.Catalog.professions = {\n")
        for pid in sorted(professions):
            p = professions[pid]
            f.write(f"  [{pid}] = {{ name = {lua_str(p['name'])}, expansions = {{")
            for eid in sorted(p["expansions"]):
                f.write(f"{eid}, ")
            f.write("} },\n")
        f.write("}\n\n")

        # Expansion (child skillLine) table
        f.write("ns.Catalog.expansions = {\n")
        for pid in sorted(professions):
            for eid in sorted(professions[pid]["expansions"]):
                e = professions[pid]["expansions"][eid]
                f.write(f"  [{eid}] = {{ name = {lua_str(e['name'])}, baseProfession = {pid}, icon = {e['icon']} }},\n")
        f.write("}\n\n")

        # Categories
        f.write("ns.Catalog.categories = {\n")
        for cid in sorted(categories):
            c = categories[cid]
            f.write(f"  [{cid}] = {{ name = {lua_str(c['name'])}, parent = {c['parent']}, skillLine = {c['skillLine']} }},\n")
        f.write("}\n\n")

        # Recipes — reagents is structured: { required = {{qty, {itemIDs}}, ...}, modifying = {...}, finishing = {...} }
        f.write("ns.Catalog.recipes = {\n")

        def emit_slot_list(slots):
            parts = []
            for slot in slots:
                qty, items = slot[0], slot[1]
                is_currency = slot[2] if len(slot) > 2 else False
                items_str = ",".join(str(i) for i in items)
                if is_currency:
                    parts.append(f"{{{qty},{{{items_str}}},c=true}}")
                else:
                    parts.append(f"{{{qty},{{{items_str}}}}}")
            return "{" + ",".join(parts) + "}"

        for rid in sorted(recipes):
            r = recipes[rid]
            rg = r["reagents"]
            req = emit_slot_list(rg["required"])
            mod = emit_slot_list(rg["modifying"])
            fin = emit_slot_list(rg["finishing"])
            # Omit empty buckets to save space.
            src = spell_to_source_item.get(rid, 0)
            parts = [f"skillLine={r['skillLine']}", f"category={r['category']}", f"item={r['item']}"]
            if src: parts.append(f"src={src}")
            reagent_parts = []
            if req != "{}": reagent_parts.append(f"required={req}")
            if mod != "{}": reagent_parts.append(f"modifying={mod}")
            if fin != "{}": reagent_parts.append(f"finishing={fin}")
            if reagent_parts:
                parts.append("reagents={" + ",".join(reagent_parts) + "}")
            f.write(f"  [{rid}] = {{{', '.join(parts)}}},\n")
        f.write("}\n")

    sys.stderr.write(
        f"done: {len(professions)} professions, "
        f"{sum(len(p['expansions']) for p in professions.values())} expansion variants, "
        f"{len(categories)} categories, {len(recipes)} recipes\n"
    )


def lua_str(s):
    s = (s or "").replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'


if __name__ == "__main__":
    main()
