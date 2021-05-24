const Migrations = artifacts.require("Stake");

module.exports = function (deployer) {
  deployer.deploy(Migrations);
};
