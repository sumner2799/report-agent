import csv

# Read pitcher tracking log
with open('pitcher_tracking_log.csv', 'r') as f:
    reader = csv.DictReader(f)
    rows = list(reader)

# Add MLB level to all rows and clean extras
for row in rows:
    if row.get('level') is None or row['level'] == '':
        row['level'] = 'MLB'
    # Remove None key if it exists
    if None in row:
        del row[None]

# Write back with new column order
fieldnames = ['pitcher_name', 'level', 'report_date', 'bip_count', 'pitch_count', 'status', 'notes']
with open('pitcher_tracking_log.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, restval='', extrasaction='ignore')
    writer.writeheader()
    writer.writerows(rows)

# Read hitter tracking log
with open('hitter_tracking_log.csv', 'r') as f:
    reader = csv.DictReader(f)
    rows = list(reader)

# Add MLB level to all rows and clean extras
for row in rows:
    if row.get('level') is None or row['level'] == '':
        row['level'] = 'MLB'
    # Remove None key if it exists
    if None in row:
        del row[None]

# Write back with new column order
fieldnames = ['batter', 'level', 'report_date', 'bip_count', 'pa_count', 'status', 'notes']
with open('hitter_tracking_log.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, restval='', extrasaction='ignore')
    writer.writeheader()
    writer.writerows(rows)

print("Updated tracking logs with level column")
