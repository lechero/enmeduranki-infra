print(
  'Start #################################################################'
);

db = db.getSiblingDB('theresai');
db.createUser({
  user: 'theresai',
  pwd: 'theresai',
  roles: [{ role: 'readWrite', db: 'theresai' }],
});

db.createCollection('models');

db = db.getSiblingDB('aimemory');
db.createUser({
  user: 'aimemory',
  pwd: 'aimemory',
  roles: [{ role: 'readWrite', db: 'aimemory' }],
});

db.createCollection('models');

print('END #################################################################');
