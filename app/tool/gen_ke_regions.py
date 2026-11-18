import re, json, sys
src = open(sys.argv[1], encoding='utf-8').read()
body = src[src.index("$cities['KE']"):src.index("return $cities;")]
names = ["Baringo","Bomet","Bungoma","Busia","Elgeyo-Marakwet","Embu","Garissa","Homa Bay","Isiolo","Kajiado","Kakamega","Kericho","Kiambu","Kilifi","Kirinyaga","Kisii","Kisumu","Kitui","Kwale","Laikipia","Lamu","Machakos","Makueni","Mandera","Marsabit","Meru","Migori","Mombasa","Murang'a","Nairobi","Nakuru","Nandi","Narok","Nyamira","Nyandarua","Nyeri","Samburu","Siaya","Taita-Taveta","Tana River","Tharaka-Nithi","Trans Nzoia","Turkana","Uasin Gishu","Vihiga","Wajir","West Pokot"]
out = []
for m in re.finditer(r"'(KE\d\d)'\s*=>\s*array\((.*?)\)\s*,?\s*(?='KE\d\d'|\)\s*;)", body, re.S):
    code, arr = m.group(1), m.group(2)
    areas = []
    for a in re.findall(r"'((?:[^'\\]|\\.)*)'", arr):
        a = a.replace("\\'", "'").strip()
        if a and a not in areas: areas.append(a)
    out.append({"code": code, "name": names[int(code[2:]) - 1], "areas": areas})
json.dump(out, open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print(len(out), sum(len(c['areas']) for c in out)); print([ (c['code'],c['name'],c['areas'][:2]) for c in out[:3]+out[-3:]])
