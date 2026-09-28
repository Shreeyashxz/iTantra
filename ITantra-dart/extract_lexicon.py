import re
import json
import os

file_path = r'd:\My FIles\Softwares\iTantra\ITantra-dart\lib\speech\indic_trans_engine.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Extract the conceptLexicon dictionary
match = re.search(r'static const Map<String, Map<String, String>> conceptLexicon = (\{.*?\});', content, re.DOTALL)
if match:
    dict_str = match.group(1)
    
    # Simple parser since it's just nested dicts with string keys and values
    # Remove comments
    dict_str = re.sub(r'//.*', '', dict_str)
    
    # Replace single quotes with double quotes. Careful with apostrophes inside words if any.
    # We can match 'key': or 'value',
    dict_str = re.sub(r"'([^']*)'", r'"\1"', dict_str)
    
    # Remove trailing commas
    dict_str = re.sub(r',\s*\}', '}', dict_str)
    
    try:
        lexicon_json = json.loads(dict_str)
        out_dir = r'd:\My FIles\Softwares\iTantra\ITantra-dart\assets\lexicons'
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, 'disaster_lexicon.json')
        with open(out_path, 'w', encoding='utf-8') as out_f:
            json.dump(lexicon_json, out_f, indent=2, ensure_ascii=False)
        print('JSON written successfully.')
    except Exception as e:
        print('Error parsing JSON:', e)
        print(dict_str[:300])
else:
    print('Could not find conceptLexicon.')
