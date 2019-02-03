/**
 * Kantpoll Project
 * https://github.com/kantpoll
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma solidity ^0.4.25;
///@title Voting with groups.
contract Campaign {
    //This represents a single voter.
    struct Voter {
        bytes32 pubkey; //The public keys that the ring signatures are composed of
        uint prefix; //02 or 03
        uint group;
        bool hasGroup; //If true, that person has already entered a group
    }

    //A group with N voters
    struct Group {
        address cPerson; //Who can vote on behalf of the other voters
        uint category; //For statistics
        uint size; //Number of voters
    }

    //Ballot info
    struct Ballot {
        bytes32 id;
        bool closed; //If it is closed, no more interaction is possible
    }

    //This struct represents a vote containing a ring signature
    struct Vote {
        bytes32 fNumber; //First number of the URS
        uint candidate; //The chosen candidate
    }

    //Before sending the vote, the voter must send a pre-vote
    struct PreVote {
        bytes20 voter; //The voter may cancel a vote with this address
        uint candidate; //The chosen candidate
    }

    //This is a type for a single candidate.
    struct Candidate {
        bytes32 website; //Candidate info
        uint votesCount; //Number of accumulated votes
    }

    //Can voters cancel their votes after being sent to candidates?
    bool public canCancel;

    //It defines what happens when users clik in candidates photos
    bool public disableCandidateLink;

    //The creator of the campaign
    address public chairperson;

    //Groups that are composed of voters
    Group[] public groups;

    //All possible group categories for groups
    bytes32[] public groupCategories;

    //Each ballot represents a round
    Ballot[] public ballots;

    //Voters, who must also be registered in groups
    mapping(address => Voter) voters;

    //User's hashcodes - should be unique
    mapping(bytes32 => bool) hashcodes;

    //How many rounds there will be
    uint public rounds;

    //How many rounds are left
    uint public remainingRounds;

    //It represents the ballot that voters are voting in
    uint public currentBallot;

    //It represents the current standard registration message that all voters must submit
    bytes32 public currentMessage;

    //It tells whether voters may enter a group
    bytes32 public stoppingAccessionToGroups;

    //Maximum group size
    uint constant public mgz = 3;

    //Info about parties, candidates etc.
    mapping(uint => bytes32) campaignIpfsInfo;

    //Group chairpersons' tor addresses
    mapping(address => mapping(uint => bytes32)) tors;

    //Group mappings
    mapping(uint => mapping(uint => address)) gVoters;

    //Ballot mapping
    mapping(uint => mapping(uint => Candidate)) bCandidates;
    uint[255] bCandidatesCounter;

    //Ballot + candidate mapping
    mapping(uint => mapping(uint => uint)) cancellations;

    //Ballot + group + fnumber mapping
    mapping(uint => mapping(uint => mapping(bytes32 => PreVote))) preVotes;

    //For statistics
    mapping(uint => mapping(uint => mapping(uint => uint))) votesPerBallotCandidateGCategory;

    //Ballot + group mappings
    mapping(uint => mapping(uint => mapping(uint => Vote))) bgVotes;
    mapping(uint => mapping(uint => mapping(uint => bool))) bgpCommitted;
    mapping(uint => mapping(uint => mapping(uint => bool))) bgpCommittedStatistics;

    //Functions

    //Create a new campaign which can have several ballots within
    function Campaign(uint r) public {
        //The maximum number of rounds is 5
        require(r > 0 && r <= 5);

        chairperson = msg.sender;
        rounds = r;
        remainingRounds = r;
    }

    //Once a pre-vote is correctly inserted, the voter can send his or her vote
    function addPreVote(uint ballot, uint group, bytes32 fnumber, bytes20 voter, uint candidate) public {
        require(preVotes[ballot][group][fnumber].voter == bytes20(0));
        preVotes[ballot][group][fnumber].voter = voter;
        preVotes[ballot][group][fnumber].candidate = candidate;
    }

    //Voters can check if their prevotes were added correctly
    function getPreVote(uint ballot, uint group, bytes32 fnumber) public view returns (bytes20 voter, uint candidate){
        voter = preVotes[ballot][group][fnumber].voter;
        candidate = preVotes[ballot][group][fnumber].candidate;
    }

    //It defines whether voters can cancel their votes after being sent to candidates
    function defineCanCancel(bool b) public {
        require(msg.sender == chairperson);
        canCancel = b;
    }

    //It defines what happens when users clik in candidates photos
    function defineDisableCandidateLink(bool b) public {
        require(msg.sender == chairperson);
        disableCandidateLink = b;
    }

    //The insertion should be done after the creation, since there will be many candidates lists
    //Different ballots may have different lists of candidates
    function addCandidateIntoBallot(uint ballot, uint position, bytes32 website) public {
        require(msg.sender == chairperson);
        require(bCandidates[ballot][position].website == bytes32(0));
        bCandidates[ballot][position].website = website;
    }

    //In order to know how many candidates there are in a ballot
    function iterateCandidatesCounter(uint ballot) public {
        bCandidatesCounter[ballot] += 1;
    }

    //Get the candidate's website
    function getCandidate(uint ballot, uint candidate) public view returns (bytes32 website, uint count){
        website = bCandidates[ballot][candidate].website;
        count = bCandidates[ballot][candidate].votesCount;
    }

    //Insert new ballot in ballots array
    function addBallot(bytes32 id) public {
        require(msg.sender == chairperson);

        //There may only be a determined number of rounds
        require(remainingRounds > 0);
        remainingRounds -= 1;

        ballots.push(Ballot({
            id : id,
            closed : false,
            stopped : false
            }));
    }

    //Voters interaction ends
    function closeBallot(uint ballot) public {
        require(msg.sender == chairperson);
        require(ballot < rounds);
        require(!ballots[ballot].closed);
        ballots[ballot].closed = true;
    }

    //The ballot must be smaller than the maximum limit
    function defineCurrentBallot(uint ballot) public {
        require(msg.sender == chairperson);
        require(ballot < rounds);
        require(!ballots[ballot].closed);
        currentBallot = ballot;
    }

    //Define the current standard vote message that all voters must submit
    function defineCurrentMessage(bytes32 message) public {
        require(msg.sender == chairperson);
        currentMessage = message;
    }

    //It tells whether voters may enter a group
    function defineStoppingAccessionToGroups(bytes32 str) public {
        require(msg.sender == chairperson);
        stoppingAccessionToGroups = str;
    }

    //It sets the group chairperson's tor addresses and pubkeys
    function defineTor(address person, uint pos, bytes32 value) public {
        require(msg.sender == person);
        tors[person][pos] = value;
    }

    //It returns the group chairperson's tor address
    function getTor(address person, uint pos) public view returns (bytes32){
        return tors[person][pos];
    }

    //Info about parties, candidates etc.
    function defineCampaignIpfsInfo(uint pos, bytes32 value) public {
        require(msg.sender == chairperson);
        campaignIpfsInfo[pos] = value;
    }

    //It returns the group chairperson's tor address
    function getCampaignIpfsInfo(uint pos) public view returns (bytes32){
        return campaignIpfsInfo[pos];
    }

    //It increases by one unit the number of cancellations of some candidate
    function incrementCancellations(uint ballot, uint candidate) public {
        require(msg.sender == chairperson);
        require(ballots[ballot].closed);

        cancellations[ballot][candidate] += 1;
    }

    //It returns the number of cancellations of some candidate
    function getCancellations(uint ballot, uint candidate) public view returns (uint){
        return cancellations[ballot][candidate];
    }

    //Adding a group with its chairperson
    function addGroup(address cPerson, uint category) public {
        require(msg.sender == chairperson);
        require(category < groupCategories.length);
        groups.push(Group({
            cPerson : cPerson,
            category : category,
            size : 0
            }));
    }

    //It adds a new unique category
    function addGroupCategory(bytes32 category) public {
        require(msg.sender == chairperson);
        require(category != bytes32(0));

        for (uint i = 0; i < groupCategories.length; i++) {
            if (groupCategories[i] == category) {
                return;
            }
        }
        groupCategories.push(category);
    }

    //Give the voter the right to vote on this ballot.
    function giveRightToVote(address toVoter, uint prefix, bytes32 pubkey, bytes32 hashcode) public {
        require(msg.sender == chairperson);
        voters[toVoter].pubkey = pubkey;
        voters[toVoter].prefix = prefix;
        hashcodes[hashcode] = true;
    }

    //If this voter is a troll
    function removeRightToVote(address toVoter) public {
        require(msg.sender == chairperson);
        voters[toVoter].prefix = 0;
    }

    //Add the voter to a group in order to he/she can vote
    function addVoterToGroup(address voter, uint grp, uint position) public {
        require(msg.sender == chairperson);
        require(!voters[voter].hasGroup);
        require(groups[grp].size < mgz);
        require(position < mgz);
        require(gVoters[grp][position] == address(0));
        //The chairperson should give right to vote to this voter first
        require(voters[voter].prefix > 0);

        //Making the voter part of a group
        voters[voter].group = grp;
        voters[voter].hasGroup = true;
        groups[grp].size += 1;
        gVoters[grp][position] = voter;
    }

    //Check whether a hashcode was inserted
    function checkHashcode(bytes32 hashcode) public view returns (bool){
        return hashcodes[hashcode];
    }

    //Get voter's info
    function getVoter(address voter) public view returns (bytes32 pubkey, uint prefix, uint group, bool hasGroup){
        pubkey = voters[voter].pubkey;
        prefix = voters[voter].prefix;
        group = voters[voter].group;
        hasGroup = voters[voter].hasGroup;
    }

    //It returns the addresses of the members of a group
    function getGroupVoters(uint group) public view returns (address[mgz]){
        address[mgz] memory addresses;
        for (uint i = 0; i < mgz; i++) {
            addresses[i] = gVoters[group][i];
        }
        return addresses;
    }

    //It returns the pubkeys of the members of a group
    function getGroupPubkeys(uint group) public view returns (uint[mgz], bytes32[mgz]){
        bytes32[mgz] memory pubkeys;
        uint[mgz] memory prefixes;

        for (uint i = 0; i < mgz; i++) {
            pubkeys[i] = voters[gVoters[group][i]].pubkey;
            prefixes[i] = voters[gVoters[group][i]].prefix;
        }
        return (prefixes, pubkeys);
    }

    //The group chairperson sends the votes
    function vote(uint ballot, uint grp, uint position, bytes32 first_number, uint the_candidate) public {
        require(msg.sender == groups[grp].cPerson);
        require(!ballots[ballot].closed);
        require(ballot < rounds);
        require(position < mgz);
        require(bgVotes[ballot][grp][position].fNumber == bytes32(0));
        require(preVotes[ballot][grp][first_number].candidate == the_candidate);
        require(preVotes[ballot][grp][first_number].voter != bytes20(0));

        //Verify if this "first number" has already been entered in the array
        for (uint i = 0; i < mgz; i++) {
            if (bgVotes[ballot][grp][i].fNumber == first_number) {
                return;
            }
        }

        bgVotes[ballot][grp][position].fNumber = first_number;
        bgVotes[ballot][grp][position].candidate = the_candidate;
    }

    //For the statistics
    function getVotesPerBallotCandidateCategory(uint ballot, uint candidate, uint category) public view returns (uint){
        return votesPerBallotCandidateGCategory[ballot][candidate][category];
    }

    //It returns all sent votes regarding a ballot and a group
    function getVotes(uint ballot, uint grp) public view returns (bytes32[mgz], uint[mgz]){
        bytes32[mgz] memory numbers;
        uint[mgz] memory candidates;
        for (uint i = 0; i < mgz; i++) {
            numbers[i] = bgVotes[ballot][grp][i].fNumber;
            candidates[i] = bgVotes[ballot][grp][i].candidate;
        }
        return (numbers, candidates);
    }

    //Check whether the the votes were committed (for that ballot, group and position), or not
    function committed(uint ballot, uint grp, uint position) public view returns (bool){
        return bgpCommitted[ballot][grp][position];
    }

    //Check whether the statistics were committed (for that ballot, group and position), or not
    function committedStatistics(uint ballot, uint grp, uint position) public view returns (bool){
        return bgpCommittedStatistics[ballot][grp][position];
    }

    //Committing the results and casting the votes
    function commitVotationPerPosition(uint ballot, uint grp, uint position) public {
        require(ballots[ballot].closed);
        //The ballot must be closed
        require(groups[grp].cPerson == msg.sender);
        //The votes must not have been committed before
        require(!bgpCommitted[ballot][grp][position]);

        if (bgVotes[ballot][grp][position].fNumber != bytes32(0)) {
            //Get the chosen candidate
            uint candidate = bgVotes[ballot][grp][position].candidate;
            //Add this vote
            bCandidates[ballot][candidate].votesCount += 1;
            bgpCommitted[ballot][grp][position] = true;
        }
    }

    //Committing the statistics regarding the votation
    function commitVotationStatisticsPerPosition(uint ballot, uint grp, uint position) public {
        require(ballots[ballot].closed);
        //The ballot must be closed
        require(groups[grp].cPerson == msg.sender);
        //The votes must not have been committed before
        require(!bgpCommittedStatistics[ballot][grp][position]);

        if (bgVotes[ballot][grp][position].fNumber != bytes32(0)) {
            //Get the chosen candidate
            uint candidate = bgVotes[ballot][grp][position].candidate;
            //Statistics
            uint category = groups[grp].category;
            votesPerBallotCandidateGCategory[ballot][candidate][category] += 1;
            bgpCommittedStatistics[ballot][grp][position] = true;
        }
    }

    //groups.length
    function howManyGroups() public view returns (uint){
        return groups.length;
    }

    //ballots.length
    function howManyBallots() public view returns (uint){
        return ballots.length;
    }

    //groupCategories.length
    function howManyGroupCategories() public view returns (uint){
        return groupCategories.length;
    }

    //Candidates length
    function howManyCandidatesInBallot(uint ballot) public view returns (uint){
        return bCandidatesCounter[ballot];
    }
}